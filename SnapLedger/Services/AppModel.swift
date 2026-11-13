import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class AppModel {
    enum ImportState: Equatable {
        case idle
        case processing(current: Int, total: Int)
        case reviewing
    }

    var ledger: Ledger?
    var ledgerURL: URL?
    var errorMessage: String?
    var importState: ImportState = .idle
    var pendingTransactions: [ParsedTransaction] = []
    var selectedTransaction: LedgerTransaction?
    var searchText = ""
    var currencyFilter: Currency?
    var typeFilter: TransactionType?
    var categoryFilter: String?
    var defaultCurrency: Currency = .CNY
    var foundationModelStatus = "正在检查…"

    private let store = LedgerStore()
    private let ocr = OCRService()
    private let parser: any TransactionParsing = FoundationModelTransactionParser()
    private var importTask: Task<Void, Never>?

    var visibleTransactions: [LedgerTransaction] {
        guard let ledger else { return [] }
        return ledger.transactions.filter { transaction in
            (searchText.isEmpty ||
             transaction.merchant.localizedCaseInsensitiveContains(searchText) ||
             transaction.category.localizedCaseInsensitiveContains(searchText)) &&
            (currencyFilter == nil || transaction.currency == currencyFilter) &&
            (typeFilter == nil || transaction.type == typeFilter) &&
            (categoryFilter == nil || transaction.category == categoryFilter)
        }.sorted { $0.date > $1.date }
    }

    var categories: [String] {
        Array(Set(ledger?.transactions.map(\.category) ?? [])).sorted()
    }

    func restoreLedger() async {
        do {
            if let restored = try await store.restore() {
                ledger = restored
                defaultCurrency = restored.defaultCurrency
                ledgerURL = await store.url
            }
        } catch {
            present(error)
        }
        updateModelStatus()
    }

    func openLedger(at url: URL) async {
        do {
            ledger = try await store.open(url)
            ledgerURL = url
            defaultCurrency = ledger?.defaultCurrency ?? .CNY
        } catch {
            present(error)
        }
    }

    func createLedger(at url: URL) async {
        do {
            ledger = try await store.create(at: url, defaultCurrency: defaultCurrency)
            ledgerURL = url
        } catch {
            present(error)
        }
    }

    func importImages(_ images: [Data]) {
        importTask?.cancel()
        importTask = Task { [weak self] in
            guard let self else { return }
            pendingTransactions.removeAll()
            importState = .processing(current: 0, total: images.count)
            var imageQueue = images
            for index in imageQueue.indices {
                let imageData = imageQueue[index]
                imageQueue[index] = Data()
                guard !Task.isCancelled else {
                    pendingTransactions.removeAll()
                    importState = .idle
                    return
                }
                do {
                    let text = try await ocr.recognize(data: imageData)
                    let parsed = try await parser.parse(text: text, defaultCurrency: defaultCurrency)
                    pendingTransactions.append(parsed)
                } catch {
                    present(error)
                }
                importState = .processing(current: index + 1, total: images.count)
            }
            importState = pendingTransactions.isEmpty ? .idle : .reviewing
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        pendingTransactions.removeAll()
        importState = .idle
    }

    func confirm(_ transaction: LedgerTransaction) async {
        guard var ledger else { return }
        var saved = transaction
        saved.updatedAt = .now
        if ledger.isDuplicate(saved) {
            errorMessage = "检测到可能重复的交易，未写入账本。请检查现有流水。"
            return
        }
        if let index = ledger.transactions.firstIndex(where: { $0.id == saved.id }) {
            ledger.transactions[index] = saved
        } else {
            ledger.transactions.append(saved)
        }
        do {
            let result = try await store.save(ledger)
            self.ledger = result.ledger
            if result.didMergeExternalChanges {
                errorMessage = "检测到其他设备更新，已按交易 UUID 合并并保留 updatedAt 较新的版本。"
            }
            pendingTransactions.removeAll { $0.transaction.id == saved.id }
            importState = pendingTransactions.isEmpty ? .idle : .reviewing
        } catch {
            present(error)
        }
    }

    func delete(_ transaction: LedgerTransaction) async {
        guard var ledger else { return }
        ledger.transactions.removeAll { $0.id == transaction.id }
        do {
            let result = try await store.save(ledger)
            self.ledger = result.ledger
            if result.didMergeExternalChanges {
                errorMessage = "检测到其他设备更新，已按交易 UUID 合并并保留 updatedAt 较新的版本。"
            }
        } catch {
            present(error)
        }
    }

    func saveSettings() async {
        guard var ledger else { return }
        ledger.defaultCurrency = defaultCurrency
        do {
            let result = try await store.save(ledger)
            self.ledger = result.ledger
            if result.didMergeExternalChanges {
                errorMessage = "检测到其他设备更新，已按交易 UUID 合并并保留 updatedAt 较新的版本。"
            }
        } catch {
            present(error)
        }
    }

    private func updateModelStatus() {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            foundationModelStatus = "可用（Apple 设备端模型）"
        case .unavailable(.deviceNotEligible):
            foundationModelStatus = "设备不支持，使用本地规则解析"
        case .unavailable(.modelNotReady):
            foundationModelStatus = "模型尚未准备好，使用本地规则解析"
        case .unavailable:
            foundationModelStatus = "当前不可用，使用本地规则解析"
        }
        #else
        foundationModelStatus = "当前系统不支持，使用本地规则解析"
        #endif
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
