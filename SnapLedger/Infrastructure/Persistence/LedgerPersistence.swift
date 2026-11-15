import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct BookmarkStore: Sendable {
    #if os(iOS)
    // Version 2 replaces the earlier minimal bookmark format, which isn't reliable for File Provider URLs.
    private let key = "ledger.securityScopedBookmark.v2"
    #else
    private let key = "ledger.securityScopedBookmark"
    #endif

    func save(url: URL) throws {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        let data = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    func restore() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
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
    private let logger = Logger(subsystem: "com.example.SnapLedger", category: "LedgerAccess")
    private(set) var url: URL?
    private var loadedData: Data?
    private let bookmarkStore = BookmarkStore()

    func restore() async throws -> Ledger? {
        do {
            guard let restoredURL = try bookmarkStore.restore() else { return nil }
            let fileExists = try withSecurityScope(restoredURL) {
                FileManager.default.fileExists(atPath: restoredURL.path)
            }
            guard fileExists else {
                bookmarkStore.clear()
                throw UserFacingError.ledgerMissing
            }
            return try open(restoredURL)
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == NSFileNoSuchFileError {
                bookmarkStore.clear()
                url = nil
                loadedData = nil
                throw UserFacingError.ledgerMissing
            }
            throw error
        }
    }

    func create(at url: URL, defaultCurrency: Currency) throws -> Ledger {
        let ledger = Ledger(defaultCurrency: defaultCurrency)
        try withSecurityScope(url) {
            let data = try LedgerCoding.encoder().encode(ledger)
            try coordinatedWrite(data, to: url)
            try bookmarkStore.save(url: url)
            loadedData = data
        }
        self.url = url
        return ledger
    }

    func open(_ url: URL) throws -> Ledger {
        logger.info("open.begin")
        do {
            let ledger: Ledger = try withSecurityScope(url) {
                logger.info("open.read.begin")
                let data = try coordinatedRead(from: url)
                logger.info("open.read.succeeded")
                guard let ledger = try? LedgerCoding.decoder().decode(Ledger.self, from: data) else {
                    throw UserFacingError.invalidLedger
                }
                logger.info("open.bookmark.begin")
                try bookmarkStore.save(url: url)
                loadedData = data
                return ledger
            }
            self.url = url
            logger.info("open.succeeded")
            return ledger
        } catch {
            let nsError = error as NSError
            logger.error("open.failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            throw error
        }
    }

    func save(_ local: Ledger) throws -> LedgerSaveResult {
        guard let url else { throw UserFacingError.permissionLost }
        logger.info("save.begin")
        do {
            let result = try withSecurityScope(url) {
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
            logger.info("save.succeeded")
            return result
        } catch {
            let nsError = error as NSError
            logger.error("save.failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            throw error
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
                // The picker grants access to the selected file, not its parent folder.
                // Data's atomic write creates and replaces its temporary representation
                // within the coordinated File Provider operation without requiring the
                // app to create an unauthorized sibling file itself.
                try data.write(to: coordinatedURL, options: .atomic)
                result = .success(())
            } catch {
                let nsError = error as NSError
                logger.error("write.failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw UserFacingError.permissionLost }
        try result.get()
    }

    private func withSecurityScope<T>(_ url: URL, operation: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        logger.info("securityScope.started=\(accessed, privacy: .public)")
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
