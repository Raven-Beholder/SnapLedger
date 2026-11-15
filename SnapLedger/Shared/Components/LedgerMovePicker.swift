#if os(iOS)
import SwiftUI
import UIKit
import OSLog

enum TemporaryLedgerFile {
    static func create(ledger: Ledger) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("ledger.json")
        let data = try LedgerCoding.encoder().encode(ledger)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func removeContainer(for sourceURL: URL) {
        try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
    }
}

struct LedgerMovePicker: UIViewControllerRepresentable {
    let sourceURL: URL
    let onPick: @MainActor (URL) async -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sourceURL: sourceURL, onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forExporting: [sourceURL],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let sourceURL: URL
        private let onPick: @MainActor (URL) async -> Void
        private let onCancel: () -> Void

        init(
            sourceURL: URL,
            onPick: @escaping @MainActor (URL) async -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.sourceURL = sourceURL
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let destinationURL = urls.first else {
                TemporaryLedgerFile.removeContainer(for: sourceURL)
                onCancel()
                return
            }
            // Document-picker URLs are security scoped. Acquire access while still
            // inside the delegate callback and retain it through opening and bookmarking.
            let hasSecurityScope = destinationURL.startAccessingSecurityScopedResource()
            Logger(subsystem: "com.example.SnapLedger", category: "LedgerAccess")
                .info("picker.securityScope.started=\(hasSecurityScope, privacy: .public)")
            Task { @MainActor in
                await onPick(destinationURL)
                if hasSecurityScope {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
                TemporaryLedgerFile.removeContainer(for: sourceURL)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            TemporaryLedgerFile.removeContainer(for: sourceURL)
            onCancel()
        }
    }
}
#endif
