import Foundation
import Observation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AnalysisTimelineEvent: Identifiable, Sendable {
    enum Kind: Sendable {
        case phase
        case tool
        case success
        case failure
    }

    let id: UUID
    let timestamp: Date
    let message: String
    let kind: Kind

    init(
        timestamp: Date = .now,
        message: String,
        kind: Kind
    ) {
        id = UUID()
        self.timestamp = timestamp
        self.message = message
        self.kind = kind
    }
}

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
    var selectedLowConfidenceFields: Set<String> = []
    var selectedParserSource = "手动编辑"
    var selectedDateSourceText: String?
    var selectedSourceImageData: Data?
    var selectedGenerationMetrics: GenerationMetrics?
    var selectedStructuredOutput: String?
    var searchText = ""
    var currencyFilter: Currency?
    var typeFilter: TransactionType?
    var categoryFilter: String?
    var defaultCurrency: Currency = .CNY
    var foundationModelStatus = "正在检查…"
    var analysisPhase = "等待导入"
    var analysisStartedAt: Date?
    var analysisEndedAt: Date?
    var analysisEvents: [AnalysisTimelineEvent] = []
    var lastGenerationMetrics: GenerationMetrics?
    var lastStructuredOutput = ""
    var lastOCRText = ""
    var lastExcludedStatusBarLines: [String] = []

    private let store = LedgerStore()
    private let logger = Logger(subsystem: "com.example.SnapLedger", category: "RecognitionPostProcessing")
    private let recognitionAgent = TransactionRecognitionAgent()
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
        guard let ledger else { return [] }
        let maintained = ledger.categories.filter { !$0.isArchived }.map(\.name)
        return Array(Set(maintained + ledger.transactions.map(\.category))).sorted()
    }

    func category(named name: String) -> LedgerCategory? {
        ledger?.category(named: name)
    }

    var paymentMethods: [String] {
        guard let ledger else { return [] }
        let historical = ledger.transactions
            .compactMap(\.paymentMethod)
            .reduce(into: [String: (name: String, count: Int)]()) { result, method in
                let trimmed = method.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let key = trimmed.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
                let current = result[key]
                result[key] = (current?.name ?? trimmed, (current?.count ?? 0) + 1)
            }
            .values
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.name < rhs.name : lhs.count > rhs.count
            }
            .map(\.name)
        return uniquePaymentMethods(ledger.paymentMethods + historical)
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

    func refreshLedger() async {
        guard let ledgerURL else { return }
        do {
            let refreshedLedger = try await store.open(ledgerURL)
            ledger = refreshedLedger
            defaultCurrency = refreshedLedger.defaultCurrency
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

    func importImages(_ images: [Data], reviewFirstWhenReady: Bool = false) {
        importTask?.cancel()
        importTask = Task { [weak self] in
            guard let self else { return }
            pendingTransactions.removeAll()
            analysisStartedAt = .now
            analysisEndedAt = nil
            analysisEvents = [
                AnalysisTimelineEvent(
                    message: "已加载 \(images.count) 张图片",
                    kind: .phase
                )
            ]
            lastGenerationMetrics = nil
            lastStructuredOutput = ""
            lastOCRText = ""
            lastExcludedStatusBarLines = []
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
                    let context = TransactionRecognitionContext(
                        defaultCurrency: defaultCurrency,
                        categoryNames: categories,
                        paymentMethodNames: paymentMethods,
                        recognitionGuidance: ledger?.recognitionGuidance ?? ""
                    )
                    analysisPhase = "识别 Agent 运行中"
                    appendAnalysisEvent(
                        "第 \(index + 1) 张：Agent 启动",
                        kind: .phase
                    )
                    var parsed = try await recognitionAgent.run(
                        imageData: imageData,
                        context: context
                    ) { [weak self] event in
                        await MainActor.run {
                            self?.analysisPhase = event.message
                            self?.appendAnalysisEvent(
                                "第 \(index + 1) 张：\(event.message)",
                                kind: Self.eventKind(for: event.message)
                            )
                        }
                    }
                    parsed.sourceImageData = imageData
                    parsed = applyingMerchantCategoryMemory(to: parsed)
                    lastGenerationMetrics = parsed.generationMetrics
                    lastStructuredOutput = parsed.modelOutput ?? "模型未提供可展示的原始结构化输出。"
                    lastOCRText = parsed.ocrText ?? ""
                    lastExcludedStatusBarLines = parsed.excludedStatusBarLines
                    appendAnalysisEvent(
                        "第 \(index + 1) 张：识别完成",
                        kind: .success
                    )
                    pendingTransactions.append(parsed)
                } catch {
                    let nsError = error as NSError
                    analysisPhase = "识别 Agent 失败"
                    var modelDiagnostic = ""
                    #if canImport(FoundationModels)
                    if #available(iOS 27.0, macOS 27.0, *),
                       case let LanguageModelError.guardrailViolation(violation) = error {
                            let metadataKeys = violation.metadata.keys.sorted().joined(separator: ", ")
                            modelDiagnostic = """
                            guardrailDebugDescription: \(violation.debugDescription)
                            guardrailMetadataKeys: \(metadataKeys.isEmpty ? "无" : metadataKeys)
                            """
                    }
                    #endif
                    lastStructuredOutput = """
                    识别 Agent 没有返回结构化交易。
                    errorDomain: \(nsError.domain)
                    errorCode: \(nsError.code)
                    message: \(nsError.localizedDescription)
                    \(modelDiagnostic)
                    """
                    appendAnalysisEvent(
                        "第 \(index + 1) 张：失败（\(nsError.domain) · \(nsError.code)）",
                        kind: .failure
                    )
                    present(error)
                }
                importState = .processing(current: index + 1, total: images.count)
            }
            importState = pendingTransactions.isEmpty ? .idle : .reviewing
            if pendingTransactions.isEmpty {
                if lastStructuredOutput.isEmpty { analysisPhase = "未生成候选交易" }
            } else {
                analysisPhase = "等待用户确认"
                if reviewFirstWhenReady, let first = pendingTransactions.first {
                    review(first)
                }
            }
            analysisEndedAt = .now
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        pendingTransactions.removeAll()
        importState = .idle
        analysisPhase = "已取消"
        analysisEndedAt = .now
    }

    func beginManualTransaction() {
        selectedLowConfidenceFields = []
        selectedParserSource = "手动录入"
        selectedDateSourceText = nil
        selectedSourceImageData = nil
        selectedGenerationMetrics = nil
        selectedStructuredOutput = nil
        selectedTransaction = LedgerTransaction(
            type: .expense,
            amount: 0,
            currency: defaultCurrency,
            merchant: "",
            category: categories.contains("其他") ? "其他" : (categories.first ?? "其他"),
            date: .now
        )
    }

    func review(_ candidate: ParsedTransaction) {
        selectedLowConfidenceFields = candidate.lowConfidenceFields
        selectedParserSource = candidate.source
        selectedDateSourceText = candidate.dateSourceText
        selectedSourceImageData = candidate.sourceImageData
        selectedGenerationMetrics = candidate.generationMetrics
        selectedStructuredOutput = candidate.modelOutput
        lastGenerationMetrics = candidate.generationMetrics
        lastStructuredOutput = candidate.modelOutput ?? "当前候选没有模型结构化输出。"
        selectedTransaction = candidate.transaction
    }

    func discardPending(_ transaction: LedgerTransaction) {
        pendingTransactions.removeAll { $0.transaction.id == transaction.id }
        advanceReviewQueue()
    }

    func closeReview() {
        selectedTransaction = nil
        selectedLowConfidenceFields = []
        selectedParserSource = "手动编辑"
        selectedDateSourceText = nil
        selectedSourceImageData = nil
        selectedGenerationMetrics = nil
        selectedStructuredOutput = nil
    }

    private func advanceReviewQueue() {
        closeReview()
        if let next = pendingTransactions.first {
            review(next)
        } else {
            importState = .idle
        }
    }

    private func applyingMerchantCategoryMemory(to parsed: ParsedTransaction) -> ParsedTransaction {
        var result = parsed
        let merchant = normalizedMerchant(parsed.transaction.merchant)
        guard !merchant.isEmpty else { return result }

        let builtInCategory = MerchantCategoryKnowledgeBase.trustedCategory(
            forMerchant: parsed.transaction.merchant
        )

        let historicalCategory = ledger?.transactions
            .filter { normalizedMerchant($0.merchant) == merchant }
            .reduce(into: [String: Int]()) { counts, transaction in
                counts[transaction.category, default: 0] += 1
            }
            .max { lhs, rhs in lhs.value < rhs.value }?.key

        guard let category = builtInCategory ?? historicalCategory,
              categories.contains(category) else { return result }
        let categorySource = builtInCategory != nil ? "builtInAlias" : "history"
        let previousCategory = result.transaction.category
        logger.info("category.override source=\(categorySource, privacy: .public) from=\(previousCategory, privacy: .public) to=\(category, privacy: .public)")
        result.transaction.category = category
        result.lowConfidenceFields.remove("category")
        result.source += " · 商户分类记忆"
        return result
    }

    private func normalizedMerchant(_ merchant: String) -> String {
        MerchantCategoryKnowledgeBase.normalize(merchant)
    }

    func confirm(_ transaction: LedgerTransaction) async {
        guard var ledger else { return }
        let wasPending = pendingTransactions.contains { $0.transaction.id == transaction.id }
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
        if let paymentMethod = saved.paymentMethod,
           !ledger.paymentMethods.contains(where: {
               $0.localizedCaseInsensitiveCompare(paymentMethod) == .orderedSame
           }) {
            ledger.paymentMethods.append(paymentMethod)
        }
        do {
            let result = try await store.save(ledger)
            self.ledger = result.ledger
            if result.didMergeExternalChanges {
                errorMessage = "检测到其他设备更新，已按交易 UUID 合并并保留 updatedAt 较新的版本。"
            }
            pendingTransactions.removeAll { $0.transaction.id == saved.id }
            importState = pendingTransactions.isEmpty ? .idle : .reviewing
            if wasPending {
                advanceReviewQueue()
            } else {
                closeReview()
            }
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

    func addCategory(name: String, kind: CategoryKind, symbolName: String) async {
        guard var ledger else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !ledger.categories.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "分类名称已存在。"
            return
        }
        ledger.categories.append(.init(name: trimmed, symbolName: symbolName, kind: kind))
        await save(ledger)
    }

    func updateCategory(_ category: LedgerCategory, previousName: String) async {
        guard var ledger, let index = ledger.categories.firstIndex(where: { $0.id == category.id }) else { return }
        var updated = category
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        updated.updatedAt = .now
        ledger.categories[index] = updated
        if previousName != updated.name {
            for index in ledger.transactions.indices where ledger.transactions[index].category == previousName {
                ledger.transactions[index].category = updated.name
                ledger.transactions[index].updatedAt = .now
            }
        }
        await save(ledger)
    }

    func deleteCategory(_ category: LedgerCategory) async {
        guard var ledger else { return }
        if ledger.transactions.contains(where: { $0.category == category.name }) {
            if let index = ledger.categories.firstIndex(where: { $0.id == category.id }) {
                ledger.categories[index].isArchived = true
                ledger.categories[index].updatedAt = .now
            }
        } else {
            ledger.categories.removeAll { $0.id == category.id }
        }
        await save(ledger)
    }

    func addPaymentMethod(_ name: String) async {
        guard var ledger else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !ledger.paymentMethods.contains(where: {
            $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            errorMessage = "支付方式已存在。"
            return
        }
        ledger.paymentMethods.append(trimmed)
        await save(ledger)
    }

    func deletePaymentMethod(_ name: String) async {
        guard var ledger else { return }
        ledger.paymentMethods.removeAll {
            $0.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        await save(ledger)
    }

    func updateRecognitionGuidance(_ guidance: String) async {
        guard var ledger else { return }
        ledger.recognitionGuidance = String(guidance.prefix(2_000))
        await save(ledger)
    }

    private func save(_ ledger: Ledger) async {
        do {
            let result = try await store.save(ledger)
            self.ledger = result.ledger
            if result.didMergeExternalChanges {
                errorMessage = "检测到其他设备更新，已合并较新的内容。"
            }
        } catch {
            present(error)
        }
    }

    private func uniquePaymentMethods(_ methods: [String]) -> [String] {
        var seen = Set<String>()
        return methods.compactMap { method in
            let trimmed = method.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func appendAnalysisEvent(
        _ message: String,
        kind: AnalysisTimelineEvent.Kind,
        timestamp: Date = .now
    ) {
        analysisEvents.append(
            AnalysisTimelineEvent(
                timestamp: timestamp,
                message: message,
                kind: kind
            )
        )
    }

    private static func eventKind(for message: String) -> AnalysisTimelineEvent.Kind {
        if message.localizedCaseInsensitiveContains("失败") ||
            message.localizedCaseInsensitiveContains("error") {
            return .failure
        }
        if message.contains("工具") || message.localizedCaseInsensitiveContains("OCR") {
            return .tool
        }
        if message.contains("完成") || message.contains("成功") {
            return .success
        }
        return .phase
    }

    private func updateModelStatus() {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            if #available(iOS 27.0, macOS 27.0, *) {
                foundationModelStatus = "可用（\(model.variant.displayName)）"
            } else {
                foundationModelStatus = "可用（Apple 设备端模型）"
            }
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

    func present(_ error: Error) {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain {
            switch cocoaError.code {
            case NSUserCancelledError:
                return
            case NSFileNoSuchFileError:
                errorMessage = UserFacingError.ledgerMissing.errorDescription
                return
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                errorMessage = UserFacingError.permissionLost.errorDescription
                return
            default:
                break
            }
        }
        if let description = (error as? LocalizedError)?.errorDescription,
           !description.isEmpty {
            errorMessage = description
        } else {
            errorMessage = "操作失败（\(cocoaError.domain) · \(cocoaError.code)）。请重试；如果仍然失败，请保留此错误码。"
        }
    }
}
