import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BookmarkStore: Sendable {
    private let key = "ledger.securityScopedBookmark"

    func save(url: URL) throws {
        #if os(macOS)
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        UserDefaults.standard.set(data, forKey: key)
    }

    func restore() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &stale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data, options: [],
            relativeTo: nil, bookmarkDataIsStale: &stale
        )
        #endif
        if stale { try save(url: url) }
        return url
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct LedgerSaveResult: Sendable {
    let ledger: Ledger
    let didMergeExternalChanges: Bool
}

actor LedgerStore {
    private(set) var url: URL?
    private var loadedData: Data?
    private let bookmarkStore = BookmarkStore()

    func restore() async throws -> Ledger? {
        guard let restoredURL = try bookmarkStore.restore() else { return nil }
        return try open(restoredURL)
    }

    func create(at url: URL, defaultCurrency: Currency) throws -> Ledger {
        let ledger = Ledger(defaultCurrency: defaultCurrency)
        try withSecurityScope(url) {
            let data = try LedgerCoding.encoder().encode(ledger)
            try coordinatedWrite(data, to: url)
            loadedData = data
        }
        self.url = url
        try bookmarkStore.save(url: url)
        return ledger
    }

    func open(_ url: URL) throws -> Ledger {
        let ledger: Ledger = try withSecurityScope(url) {
            let data = try coordinatedRead(from: url)
            guard let ledger = try? LedgerCoding.decoder().decode(Ledger.self, from: data) else {
                throw UserFacingError.invalidLedger
            }
            loadedData = data
            return ledger
        }
        self.url = url
        try bookmarkStore.save(url: url)
        return ledger
    }

    func save(_ local: Ledger) throws -> LedgerSaveResult {
        guard let url else { throw UserFacingError.permissionLost }
        return try withSecurityScope(url) {
            let currentData = try coordinatedRead(from: url)
            var ledgerToWrite = local
            let didMergeExternalChanges = loadedData.map { currentData != $0 } ?? false
            if didMergeExternalChanges {
                guard let remote = try? LedgerCoding.decoder().decode(Ledger.self, from: currentData) else {
                    throw UserFacingError.invalidLedger
                }
                ledgerToWrite = Ledger.merged(local: local, remote: remote)
            }
            let newData = try LedgerCoding.encoder().encode(ledgerToWrite)
            try coordinatedWrite(newData, to: url)
            loadedData = newData
            return LedgerSaveResult(
                ledger: ledgerToWrite,
                didMergeExternalChanges: didMergeExternalChanges
            )
        }
    }

    private func coordinatedRead(from url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            do { result = .success(try Data(contentsOf: $0)) }
            catch { result = .failure(error) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw UserFacingError.permissionLost }
        return try result.get()
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) {
            coordinatedURL in
            do {
                let directory = coordinatedURL.deletingLastPathComponent()
                let temporaryURL = directory.appendingPathComponent(".ledger-\(UUID().uuidString).tmp")
                try data.write(to: temporaryURL, options: .atomic)
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    _ = try FileManager.default.replaceItemAt(
                        coordinatedURL, withItemAt: temporaryURL,
                        backupItemName: nil, options: .usingNewMetadataOnly
                    )
                } else {
                    try FileManager.default.moveItem(at: temporaryURL, to: coordinatedURL)
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw UserFacingError.permissionLost }
        try result.get()
    }

    private func withSecurityScope<T>(_ url: URL, operation: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }
}

struct CSVExporter: Sendable {
    func data(for ledger: Ledger) -> Data {
        var rows = ["id,type,amount,currency,merchant,category,date,paymentMethod,note,createdAt,updatedAt"]
        let formatter = ISO8601DateFormatter()
        for item in ledger.transactions {
            let values = [
                item.id.uuidString, item.type.rawValue, DecimalCoding.string(from: item.amount),
                item.currency.rawValue, item.merchant, item.category, formatter.string(from: item.date),
                item.paymentMethod ?? "", item.note ?? "", formatter.string(from: item.createdAt),
                formatter.string(from: item.updatedAt)
            ]
            rows.append(values.map(escape).joined(separator: ","))
        }
        return Data((rows.joined(separator: "\n") + "\n").utf8)
    }

    private func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

struct LedgerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var ledger: Ledger

    init(ledger: Ledger) { self.ledger = ledger }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw UserFacingError.invalidLedger }
        ledger = try LedgerCoding.decoder().decode(Ledger.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try LedgerCoding.encoder().encode(ledger))
    }
}
