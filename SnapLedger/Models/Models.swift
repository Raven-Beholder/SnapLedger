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
            transactions: merged.values.sorted { $0.date > $1.date }
        )
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
