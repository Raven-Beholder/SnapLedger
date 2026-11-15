import Foundation

enum Currency: String, Codable, CaseIterable, Identifiable, Sendable {
    case CNY, USD, HKD
    var id: Self { self }
    var displayName: String {
        switch self {
        case .CNY: "人民币"
        case .USD: "美元"
        case .HKD: "港币"
        }
    }
}

enum TransactionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case income, expense, refund, transfer
    var id: Self { self }
    var displayName: String {
        switch self {
        case .income: "收入"
        case .expense: "支出"
        case .refund: "退款"
        case .transfer: "转账"
        }
    }
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense, income
    var id: Self { self }
    var displayName: String { self == .expense ? "支出" : "收入" }
}

struct LedgerCategory: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var symbolName: String
    var kind: CategoryKind
    var isArchived: Bool = false
    var updatedAt: Date = .now

    static let defaults: [LedgerCategory] = [
        .init(name: "餐饮", symbolName: "fork.knife", kind: .expense),
        .init(name: "交通", symbolName: "car.fill", kind: .expense),
        .init(name: "购物", symbolName: "bag.fill", kind: .expense),
        .init(name: "居住", symbolName: "house.fill", kind: .expense),
        .init(name: "旅行", symbolName: "airplane", kind: .expense),
        .init(name: "医疗", symbolName: "cross.case.fill", kind: .expense),
        .init(name: "娱乐", symbolName: "gamecontroller.fill", kind: .expense),
        .init(name: "教育", symbolName: "book.fill", kind: .expense),
        .init(name: "其他", symbolName: "ellipsis.circle.fill", kind: .expense),
        .init(name: "工资", symbolName: "banknote.fill", kind: .income),
        .init(name: "奖金", symbolName: "gift.fill", kind: .income),
        .init(name: "投资收益", symbolName: "chart.line.uptrend.xyaxis", kind: .income),
        .init(name: "其他收入", symbolName: "plus.circle.fill", kind: .income)
    ]
}

struct LedgerTransaction: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var type: TransactionType
    var amount: Decimal
    var currency: Currency
    var merchant: String
    var category: String
    var date: Date
    var paymentMethod: String?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(), type: TransactionType = .expense, amount: Decimal = 0,
        currency: Currency = .CNY, merchant: String = "", category: String = "其他",
        date: Date = .now, paymentMethod: String? = nil, note: String? = nil,
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.category = category
        self.date = date
        self.paymentMethod = paymentMethod
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, type, amount, currency, merchant, category, date
        case paymentMethod, note, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        type = try values.decode(TransactionType.self, forKey: .type)
        amount = try DecimalCoding.decode(from: values, forKey: .amount)
        currency = try values.decode(Currency.self, forKey: .currency)
        merchant = try values.decode(String.self, forKey: .merchant)
        category = try values.decode(String.self, forKey: .category)
        date = try values.decode(Date.self, forKey: .date)
        paymentMethod = try values.decodeIfPresent(String.self, forKey: .paymentMethod)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(type, forKey: .type)
        try DecimalCoding.encode(amount, to: &values, forKey: .amount)
        try values.encode(currency, forKey: .currency)
        try values.encode(merchant, forKey: .merchant)
        try values.encode(category, forKey: .category)
        try values.encode(date, forKey: .date)
        try values.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
        try values.encodeIfPresent(note, forKey: .note)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

struct Ledger: Codable, Sendable {
    var version: Int = 1
    var defaultCurrency: Currency = .CNY
    var transactions: [LedgerTransaction] = []
    var categories: [LedgerCategory] = LedgerCategory.defaults
    var paymentMethods: [String] = []
    var recognitionGuidance: String = ""

    enum CodingKeys: String, CodingKey {
        case version, defaultCurrency, transactions, categories, paymentMethods, recognitionGuidance
    }

    init(
        version: Int = 1,
        defaultCurrency: Currency = .CNY,
        transactions: [LedgerTransaction] = [],
        categories: [LedgerCategory] = LedgerCategory.defaults,
        paymentMethods: [String] = [],
        recognitionGuidance: String = ""
    ) {
        self.version = version
        self.defaultCurrency = defaultCurrency
        self.transactions = transactions
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.recognitionGuidance = recognitionGuidance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        defaultCurrency = try values.decodeIfPresent(Currency.self, forKey: .defaultCurrency) ?? .CNY
        transactions = try values.decodeIfPresent([LedgerTransaction].self, forKey: .transactions) ?? []
        categories = try values.decodeIfPresent([LedgerCategory].self, forKey: .categories) ?? LedgerCategory.defaults
        let storedPaymentMethods = try values.decodeIfPresent([String].self, forKey: .paymentMethods)
        paymentMethods = storedPaymentMethods ?? Self.uniquePaymentMethods(
            transactions.compactMap(\.paymentMethod)
        )
        recognitionGuidance = try values.decodeIfPresent(String.self, forKey: .recognitionGuidance) ?? ""
    }

    static func merged(local: Ledger, remote: Ledger) -> Ledger {
        var merged = Dictionary(uniqueKeysWithValues: local.transactions.map { ($0.id, $0) })
        for transaction in remote.transactions {
            if let current = merged[transaction.id] {
                merged[transaction.id] = transaction.updatedAt > current.updatedAt ? transaction : current
            } else {
                merged[transaction.id] = transaction
            }
        }
        return Ledger(
            version: max(local.version, remote.version),
            defaultCurrency: local.defaultCurrency,
            transactions: merged.values.sorted { $0.date > $1.date },
            categories: mergedCategories(local: local.categories, remote: remote.categories),
            paymentMethods: uniquePaymentMethods(local.paymentMethods + remote.paymentMethods),
            recognitionGuidance: local.recognitionGuidance.isEmpty ? remote.recognitionGuidance : local.recognitionGuidance
        )
    }

    private static func mergedCategories(
        local: [LedgerCategory], remote: [LedgerCategory]
    ) -> [LedgerCategory] {
        var result = local
        for category in remote {
            if let index = result.firstIndex(where: { $0.id == category.id }) {
                if category.updatedAt > result[index].updatedAt {
                    result[index] = category
                }
            } else {
                result.append(category)
            }
        }
        return result
    }

    private static func uniquePaymentMethods(_ methods: [String]) -> [String] {
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

    func category(named name: String) -> LedgerCategory? {
        let lookup = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return categories.first {
            $0.name.localizedCaseInsensitiveCompare(lookup) == .orderedSame
        }
    }

    var knownCategoryNames: [String] {
        var names: [String] = []
        var seen = Set<String>()

        func append(_ name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { return }
            names.append(trimmed)
        }

        for category in categories {
            append(category.name)
        }
        for name in transactions.map(\.category).sorted() {
            append(name)
        }
        return names
    }

    func isDuplicate(_ candidate: LedgerTransaction) -> Bool {
        transactions.contains {
            $0.id != candidate.id &&
            $0.amount == candidate.amount &&
            $0.currency == candidate.currency &&
            $0.merchant.localizedCaseInsensitiveCompare(candidate.merchant) == .orderedSame &&
            abs($0.date.timeIntervalSince(candidate.date)) < 300
        }
    }
}
