import AppIntents
import Foundation

struct GetSnapLedgerCloudPromptIntent: AppIntent {
    static let title: LocalizedStringResource = "获取 SnapLedger 云端解析指令"
    static let description = IntentDescription("返回适用于快捷指令“使用模型”动作的交易提取指令。")

    func perform() async throws -> some ReturnsValue<String> {
        let ledger = try? await LedgerStore().restore()
        return .result(value: CloudModelShortcutImport.prompt(for: ledger))
    }
}

struct ImportCloudModelResultIntent: AppIntent {
    static let title: LocalizedStringResource = "导入云端模型结果到 SnapLedger"
    static let description = IntentDescription("校验云端模型返回的 JSON，并将交易写入当前账本。")

    @Parameter(title: "模型输出")
    var modelOutput: String

    static var parameterSummary: some ParameterSummary {
        Summary("导入 \(\.$modelOutput)")
    }

    func perform() async throws -> some ReturnsValue<Int> & ProvidesDialog {
        let store = LedgerStore()
        guard var ledger = try await store.restore() else {
            throw CloudShortcutIntentError.ledgerUnavailable
        }

        let candidates: [LedgerTransaction]
        do {
            candidates = try CloudModelShortcutImport.transactions(from: modelOutput, ledger: ledger)
        } catch CloudImportError.needsConfirmation {
            throw CloudShortcutIntentError.needsConfirmation
        } catch CloudImportError.invalidTransaction {
            throw CloudShortcutIntentError.invalidTransaction
        } catch {
            throw CloudShortcutIntentError.invalidJSON
        }

        var importedCount = 0
        for candidate in candidates where !ledger.isDuplicate(candidate) {
            ledger.transactions.append(candidate)
            importedCount += 1
        }

        if importedCount > 0 {
            _ = try await store.save(ledger)
        }

        return .result(
            value: importedCount,
            dialog: "已导入 \(importedCount) 笔新交易；重复交易已自动跳过。"
        )
    }
}

enum CloudModelShortcutImport {
    static var prompt: String { prompt(for: nil) }

    static func prompt(for ledger: Ledger?) -> String {
        let categories = ledger?.knownCategoryNames ?? LedgerCategory.defaults.map(\.name)
        let paymentMethods = ledger?.paymentMethods ?? []
        let guidance = ledger?.recognitionGuidance ?? ""
        return TransactionRecognitionPrompts.imageAnalysis(
            categoryNames: categories,
            paymentMethodNames: paymentMethods,
            recognitionGuidance: guidance
        ) + """

        Return JSON only, with no Markdown or explanation.
    Use exactly this schema:
    {
      "transactions": [
        {
          "type": "expense | income | refund | transfer",
          "amount": "positive decimal number copied from the screenshot",
          "currency": "CNY | USD | HKD",
          "merchant": "merchant or payee copied from visible text",
          "category": "餐饮 | 交通 | 购物 | 居住 | 旅行 | 医疗 | 娱乐 | 教育 | 工资 | 奖金 | 投资收益 | 其他",
          "date": "YYYY-MM-DD HH:mm",
          "paymentMethod": "visible payment method or empty string",
          "note": "short visible context or empty string",
          "needsConfirmation": []
        }
      ]
    }
    Never infer an amount, merchant, currency, date, payment method, or hidden card digits.
    If any required field is missing or uncertain, list its JSON key in needsConfirmation.
    """
    }

    static func transactions(from modelOutput: String, ledger: Ledger) throws -> [LedgerTransaction] {
        let data = try jsonData(from: modelOutput)
        let decoder = JSONDecoder()
        let payloads: [CloudTransactionPayload]
        if let envelope = try? decoder.decode(CloudTransactionEnvelope.self, from: data) {
            payloads = envelope.transactions
        } else if let payload = try? decoder.decode(CloudTransactionPayload.self, from: data) {
            payloads = [payload]
        } else {
            throw CloudImportError.invalidJSON
        }
        guard !payloads.isEmpty else { throw CloudImportError.empty }
        return try payloads.map { try transaction(from: $0, ledger: ledger) }
    }

    private static func jsonData(from text: String) throws -> Data {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            throw CloudImportError.invalidJSON
        }
        return Data(text[start...end].utf8)
    }

    private static func transaction(
        from payload: CloudTransactionPayload,
        ledger: Ledger
    ) throws -> LedgerTransaction {
        guard payload.needsConfirmation.isEmpty else { throw CloudImportError.needsConfirmation }
        guard let type = transactionType(from: payload.type),
              let amount = DecimalCoding.decimal(from: payload.amount),
              amount > 0,
              let currency = Currency(rawValue: payload.currency.uppercased()),
              let date = DateParsing.resolve(payload.date)?.date else {
            throw CloudImportError.invalidTransaction
        }

        let merchant = payload.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty else { throw CloudImportError.invalidTransaction }

        let knownCategories = ledger.knownCategoryNames
        let proposedCategory = payload.category ?? "其他"
        let category = knownCategories.contains(proposedCategory)
            ? proposedCategory
            : (knownCategories.contains("其他") ? "其他" : (knownCategories.first ?? "其他"))

        return LedgerTransaction(
            type: type,
            amount: amount,
            currency: currency,
            merchant: merchant,
            category: category,
            date: date,
            paymentMethod: nilIfEmpty(payload.paymentMethod),
            note: nilIfEmpty(payload.note)
        )
    }

    private static func transactionType(from value: String) -> TransactionType? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "expense", "支出": .expense
        case "income", "收入": .income
        case "refund", "退款": .refund
        case "transfer", "转账": .transfer
        default: nil
        }
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CloudTransactionEnvelope: Decodable {
    let transactions: [CloudTransactionPayload]
}

private struct CloudTransactionPayload: Decodable {
    let type: String
    let amount: String
    let currency: String
    let merchant: String
    let category: String?
    let date: String
    let paymentMethod: String?
    let note: String?
    let needsConfirmation: [String]

    private enum CodingKeys: String, CodingKey {
        case type, amount, currency, merchant, category, date, paymentMethod, note, needsConfirmation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        if let stringAmount = try? container.decode(String.self, forKey: .amount) {
            amount = stringAmount
        } else {
            amount = String(try container.decode(Double.self, forKey: .amount))
        }
        currency = try container.decode(String.self, forKey: .currency)
        merchant = try container.decode(String.self, forKey: .merchant)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        date = try container.decode(String.self, forKey: .date)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        needsConfirmation = try container.decodeIfPresent([String].self, forKey: .needsConfirmation) ?? []
    }
}

private enum CloudImportError: Error {
    case invalidJSON
    case empty
    case needsConfirmation
    case invalidTransaction
}

private enum CloudShortcutIntentError: Error, CustomLocalizedStringResourceConvertible {
    case ledgerUnavailable
    case invalidJSON
    case needsConfirmation
    case invalidTransaction

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .ledgerUnavailable:
            "请先在 SnapLedger 中创建或打开账本。"
        case .invalidJSON:
            "没有读取到交易 JSON。请用“快速查看”检查“使用模型”的回应内容。"
        case .needsConfirmation:
            "模型标记了不确定字段，因此未写入账本。请检查原图后重试。"
        case .invalidTransaction:
            "JSON 已读取，但金额、币种、商户或日期格式无效。"
        }
    }
}
