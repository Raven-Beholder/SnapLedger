import Foundation
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ParsedTransaction: Sendable {
    var transaction: LedgerTransaction
    var lowConfidenceFields: Set<String>
    var source: String
}

protocol TransactionParsing: Sendable {
    func parse(text: String, defaultCurrency: Currency) async throws -> ParsedTransaction
}

struct FallbackTransactionParser: TransactionParsing {
    let primary: (any TransactionParsing)?
    let fallback: any TransactionParsing

    init(primary: (any TransactionParsing)?, fallback: any TransactionParsing = RuleBasedTransactionParser()) {
        self.primary = primary
        self.fallback = fallback
    }

    func parse(text: String, defaultCurrency: Currency) async throws -> ParsedTransaction {
        if let primary {
            do { return try await primary.parse(text: text, defaultCurrency: defaultCurrency) }
            catch { return try await fallback.parse(text: text, defaultCurrency: defaultCurrency) }
        }
        return try await fallback.parse(text: text, defaultCurrency: defaultCurrency)
    }
}

struct OCRService: Sendable {
    func recognize(data: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US")
        ]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: data)
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UserFacingError.noText
        }
        return text
    }
}

struct RuleBasedTransactionParser: TransactionParsing {
    func parse(text: String, defaultCurrency: Currency) async throws -> ParsedTransaction {
        guard let match = bestAmountMatch(in: text) else { throw UserFacingError.missingAmount }
        guard let amount = DecimalCoding.decimal(from: match.amount), amount > 0 else {
            throw UserFacingError.invalidAmount
        }
        let date = extractDate(from: text) ?? .now
        let method = paymentMethod(in: text)
        let type: TransactionType = text.contains("退款") ? .refund :
            (text.contains("收入") || text.contains("收款")) ? .income :
            text.contains("转账") ? .transfer : .expense
        let merchant = extractMerchant(from: text)
        let transaction = LedgerTransaction(
            type: type,
            amount: amount,
            currency: match.currency ?? defaultCurrency,
            merchant: merchant,
            category: category(in: text),
            date: date,
            paymentMethod: method
        )
        var uncertain: Set<String> = []
        if match.currency == nil { uncertain.insert("currency") }
        if extractDate(from: text) == nil { uncertain.insert("date") }
        if merchant.isEmpty { uncertain.insert("merchant") }
        return ParsedTransaction(transaction: transaction, lowConfidenceFields: uncertain, source: "本地规则")
    }

    private func bestAmountMatch(in text: String) -> (amount: String, currency: Currency?)? {
        let preferredLabels = ["实付", "支付金额", "扣款金额", "交易金额", "付款金额"]
        for label in preferredLabels {
            if let line = text.components(separatedBy: .newlines).first(where: { $0.contains(label) }),
               let match = firstAmount(in: line) { return match }
        }
        return firstAmount(in: text)
    }

    private func firstAmount(in text: String) -> (String, Currency?)? {
        let patterns: [(String, Currency)] = [
            (#"HK\$\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .HKD),
            (#"HKD\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .HKD),
            (#"(?:US\$|USD)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .USD),
            (#"[$]\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .USD),
            (#"(?:¥|￥|CNY)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .CNY)
        ]
        for (pattern, currency) in patterns {
            if let result = capture(pattern, in: text) { return (result, currency) }
        }
        if let result = capture(#"(?<![0-9])([0-9][0-9,]*\.[0-9]{2})(?![0-9])"#, in: text) {
            return (result, nil)
        }
        return nil
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func extractDate(from text: String) -> Date? {
        let patterns = [
            #"[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日(?:\s+[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)?"#,
            #"[0-9]{4}-[0-9]{2}-[0-9]{2}(?:[T\s][0-9]{2}:[0-9]{2}(?::[0-9]{2})?(?:[+-][0-9]{2}:[0-9]{2}|Z)?)?"#,
            #"[0-9]{1,2}月[0-9]{1,2}日\s+[0-9]{1,2}:[0-9]{2}"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else { continue }
            if let date = DateParsing.parse(String(text[range])) { return date }
        }
        return nil
    }

    private func paymentMethod(in text: String) -> String? {
        for method in ["微信支付", "支付宝", "Apple Pay", "银行卡", "信用卡", "借记卡"] {
            if text.localizedCaseInsensitiveContains(method) { return method }
        }
        return nil
    }

    private func category(in text: String) -> String {
        let mappings = [("咖啡", "餐饮"), ("餐", "餐饮"), ("打车", "交通"), ("地铁", "交通"),
                        ("酒店", "旅行"), ("超市", "购物"), ("退款", "退款")]
        return mappings.first(where: { text.contains($0.0) })?.1 ?? "其他"
    }

    private func extractMerchant(from text: String) -> String {
        let ignored = ["实付", "支付金额", "扣款金额", "交易金额", "订单号", "余额", "优惠"]
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                line.count >= 2 && line.count <= 40 &&
                !ignored.contains(where: line.contains) &&
                line.range(of: #"[¥￥$]|CNY|USD|HKD|\d{4}[-年]"#, options: .regularExpression) == nil
            } ?? ""
    }
}

#if canImport(FoundationModels)
@Generable
struct GeneratedTransactionCandidate {
    @Guide(description: "Only income, expense, refund, or transfer")
    var transactionType: String
    @Guide(description: "The exact transaction amount text from the input, without calculating")
    var amountText: String
    @Guide(description: "Only CNY, USD, or HKD")
    var currencyCode: String
    var merchant: String
    var category: String
    var dateText: String
    var paymentMethod: String
    var note: String
    @Guide(description: "Fields requiring human confirmation")
    var needsConfirmation: [String]
}

struct FoundationModelTransactionParser: TransactionParsing {
    private let fallback = RuleBasedTransactionParser()

    func parse(text: String, defaultCurrency: Currency) async throws -> ParsedTransaction {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return try await fallback.parse(text: text, defaultCurrency: defaultCurrency)
        }
        let instructions = """
        Extract exactly one transaction from OCR text. Only output CNY, USD, or HKD.
        Never calculate or invent an amount. Prefer 实付, 支付金额, 扣款金额, or 交易金额.
        Distinguish original price, discounts, balance, and actual paid amount.
        Never treat order numbers, balances, or discounts as transaction amounts.
        Recognize 微信支付, 支付宝, Apple Pay, and bank cards.
        Mark amount, currency, or date in needsConfirmation whenever uncertain.
        ¥ means CNY, HK$ means HKD, and $ means USD.
        """
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(to: text, generating: GeneratedTransactionCandidate.self)
            return try validate(response.content, defaultCurrency: defaultCurrency)
        } catch {
            return try await fallback.parse(text: text, defaultCurrency: defaultCurrency)
        }
    }

    private func validate(
        _ candidate: GeneratedTransactionCandidate, defaultCurrency: Currency
    ) throws -> ParsedTransaction {
        guard let amount = DecimalCoding.decimal(from: candidate.amountText), amount > 0 else {
            throw UserFacingError.invalidAmount
        }
        guard let currency = Currency(rawValue: candidate.currencyCode.uppercased()) else {
            throw UserFacingError.message("模型返回了不支持的币种，请手动修改。")
        }
        let type = TransactionType(rawValue: candidate.transactionType.lowercased()) ?? .expense
        let date = DateParsing.parse(candidate.dateText) ?? .now
        var uncertain = Set(candidate.needsConfirmation)
        if DateParsing.parse(candidate.dateText) == nil { uncertain.insert("date") }
        if candidate.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            uncertain.insert("merchant")
        }
        let transaction = LedgerTransaction(
            type: type, amount: amount, currency: currency,
            merchant: candidate.merchant, category: candidate.category.isEmpty ? "其他" : candidate.category,
            date: date,
            paymentMethod: candidate.paymentMethod.isEmpty ? nil : candidate.paymentMethod,
            note: candidate.note.isEmpty ? nil : candidate.note
        )
        return ParsedTransaction(transaction: transaction, lowConfidenceFields: uncertain, source: "Apple 设备端模型")
    }
}
#else
struct FoundationModelTransactionParser: TransactionParsing {
    func parse(text: String, defaultCurrency: Currency) async throws -> ParsedTransaction {
        try await RuleBasedTransactionParser().parse(text: text, defaultCurrency: defaultCurrency)
    }
}
#endif
