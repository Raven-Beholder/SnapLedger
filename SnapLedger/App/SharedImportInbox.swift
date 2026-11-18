import Foundation

enum SharedImportInbox {
    static let appGroupIdentifier = "group.com.chenxuanchi.SnapLedger"
    static let deepLinkScheme = "snapledger"

    static func consumePendingImages() -> [Data] {
        guard let inboxURL else { return [] }

        let fileManager = FileManager.default
        let batches = (try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.lastPathComponent.hasPrefix("batch-") } ?? []

        var images: [Data] = []
        for batchURL in batches.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let imageURLs = (try? fileManager.contentsOfDirectory(
                at: batchURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) ?? []

            let batchImages = imageURLs.compactMap { try? Data(contentsOf: $0) }
            guard !batchImages.isEmpty else { continue }
            images.append(contentsOf: batchImages)
            try? fileManager.removeItem(at: batchURL)
        }
        return images
    }

    private static var inboxURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        return containerURL.appending(path: "SharedImportInbox", directoryHint: .isDirectory)
    }
}
