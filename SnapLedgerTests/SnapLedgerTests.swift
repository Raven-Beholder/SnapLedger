import Foundation
import Testing
@testable import SnapLedger

struct SnapLedgerTests {
    @Test func decimalStringCodingForAllCurrencies() throws {
        for currency in Currency.allCases {
            let transaction = LedgerTransaction(amount: Decimal(string: "28.50")!, currency: currency)
            let data = try LedgerCoding.encoder().encode(transaction)
            let json = String(decoding: data, as: UTF8.self)
            #expect(json.contains(#""amount" : "28.5""#))
            let decoded = try LedgerCoding.decoder().decode(LedgerTransaction.self, from: data)
            #expect(decoded.amount == Decimal(string: "28.50"))
            #expect(decoded.currency == currency)
        }
    }

    @Test(arguments: [
        ("28.50", "28.50"), ("1,234.56", "1234.56"), ("+12.99", "12.99")
    ])
    func amountParsing(input: String, expected: String) {
        #expect(DecimalCoding.decimal(from: input) == Decimal(string: expected))
    }

    @Test(arguments: [
        ("实付 ¥28.50", Currency.CNY, "28.50"),
        ("实付 ￥28.50", Currency.CNY, "28.50"),
        ("CNY 28.50", Currency.CNY, "28.50"),
        ("支付金额 $12.99", Currency.USD, "12.99"),
        ("US$12.99", Currency.USD, "12.99"),
        ("USD 12.99", Currency.USD, "12.99"),
        ("HK$88.00", Currency.HKD, "88.00"),
        ("HKD 88.00", Currency.HKD, "88.00")
    ])
    func currencySymbols(sample: String, currency: Currency, amount: String) async throws {
        let result = try await RuleBasedTransactionParser().parse(text: sample, defaultCurrency: .CNY)
        #expect(result.transaction.currency == currency)
        #expect(result.transaction.amount == Decimal(string: amount))
    }

    @Test func chineseAndISODateParsing() {
        #expect(DateParsing.parse("2026年11月13日 09:42") != nil)
        #expect(DateParsing.parse("2026-11-13T09:42:00+08:00") != nil)
        #expect(DateParsing.parse("2026/11/13 09:42") != nil)
        #expect(DateParsing.parse("2026.11.13 09:42") != nil)
    }

    @Test func missingYearUsesMostRecentNonFutureDate() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-02T10:00:00+08:00"))
        let result = try #require(DateParsing.resolve("12月31日 23:30", now: now))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: result.date)
        #expect(components.year == 2025)
        #expect(components.month == 12)
        #expect(components.day == 31)
        #expect(result.precision == .missingYear)
        #expect(result.requiresConfirmation)
    }

    @Test func relativeAndTimeOnlyDatesRequireConfirmation() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-14T00:10:00+08:00"))
        let yesterday = try #require(DateParsing.resolve("昨天 15:39", now: now))
        let timeOnly = try #require(DateParsing.resolve("23:50", now: now))
        #expect(yesterday.precision == .relativeDate)
        #expect(timeOnly.precision == .timeOnly)
        #expect(yesterday.requiresConfirmation)
        #expect(timeOnly.requiresConfirmation)
        #expect(timeOnly.date < now)
    }

    @Test func invalidOrAbsentDateDoesNotParse() {
        #expect(DateParsing.resolve("") == nil)
        #expect(DateParsing.resolve("2026年2月30日 09:42") == nil)
        #expect(DateParsing.resolve("25:99") == nil)
    }

    @Test func ledgerJSONRoundTrip() throws {
        let ledger = Ledger(transactions: [
            LedgerTransaction(amount: Decimal(string: "28.50")!, merchant: "瑞幸咖啡")
        ])
        let data = try LedgerCoding.encoder().encode(ledger)
        let decoded = try LedgerCoding.decoder().decode(Ledger.self, from: data)
        #expect(decoded.version == 1)
        #expect(decoded.transactions.first?.merchant == "瑞幸咖啡")
        #expect(decoded.transactions.first?.amount == Decimal(string: "28.50"))
    }

    @Test func ledgerPersistsMaintainedPaymentMethods() throws {
        let ledger = Ledger(paymentMethods: ["微信支付", "Visa •••• 1234"])
        let data = try LedgerCoding.encoder().encode(ledger)
        let decoded = try LedgerCoding.decoder().decode(Ledger.self, from: data)
        #expect(decoded.paymentMethods == ["微信支付", "Visa •••• 1234"])
    }

    @Test func shortcutModelJSONCreatesTransaction() throws {
        let json = """
        {
          "transactions": [{
            "type": "expense",
            "amount": "28.50",
            "currency": "CNY",
            "merchant": "瑞幸咖啡",
            "category": "餐饮",
            "date": "2026-11-15 12:42",
            "paymentMethod": "微信支付",
            "note": "咖啡",
            "needsConfirmation": []
          }]
        }
        """

        let transactions = try CloudModelShortcutImport.transactions(from: json, ledger: Ledger())
        let transaction = try #require(transactions.first)
        #expect(transaction.amount == Decimal(string: "28.50"))
        #expect(transaction.currency == .CNY)
        #expect(transaction.merchant == "瑞幸咖啡")
        #expect(transaction.category == "餐饮")
        #expect(transaction.paymentMethod == "微信支付")
    }

    @Test func shortcutModelJSONRejectsUncertainFields() {
        let json = """
        {
          "transactions": [{
            "type": "expense",
            "amount": "28.50",
            "currency": "CNY",
            "merchant": "",
            "category": "其他",
            "date": "2026-11-15 12:42",
            "paymentMethod": "",
            "note": "",
            "needsConfirmation": ["merchant"]
          }]
        }
        """

        #expect(throws: (any Error).self) {
            try CloudModelShortcutImport.transactions(from: json, ledger: Ledger())
        }
    }

    @Test func oldLedgerMigratesPaymentMethodsFromTransactions() throws {
        let json = """
        {
          "version" : 1,
          "defaultCurrency" : "CNY",
          "transactions" : [{
            "id" : "00000000-0000-0000-0000-000000000001",
            "type" : "expense",
            "amount" : "10",
            "currency" : "CNY",
            "merchant" : "测试商户",
            "category" : "其他",
            "date" : "2026-11-15T00:00:00Z",
            "paymentMethod" : "支付宝",
            "createdAt" : "2026-11-15T00:00:00Z",
            "updatedAt" : "2026-11-15T00:00:00Z"
          }],
          "categories" : [],
          "recognitionGuidance" : ""
        }
        """
        let ledger = try LedgerCoding.decoder().decode(Ledger.self, from: Data(json.utf8))
        #expect(ledger.paymentMethods == ["支付宝"])
    }

    @Test func categoryLookupIgnoresCaseAndWhitespace() throws {
        let ledger = Ledger(categories: [
            .init(name: "餐饮", symbolName: "fork.knife", kind: .expense),
            .init(name: "Old", symbolName: "archivebox.fill", kind: .expense, isArchived: true)
        ])
        #expect(ledger.category(named: " 餐饮 ")?.symbolName == "fork.knife")
        #expect(ledger.category(named: "old")?.symbolName == "archivebox.fill")
        #expect(ledger.category(named: "未知分类") == nil)
    }

    @Test func knownCategoryNamesKeepOrderAndAppendHistory() {
        let ledger = Ledger(
            transactions: [
                LedgerTransaction(category: "自定义"),
                LedgerTransaction(category: "餐饮")
            ],
            categories: [
                LedgerCategory(name: "餐饮", symbolName: "fork.knife", kind: .expense),
                LedgerCategory(name: "交通", symbolName: "car.fill", kind: .expense)
            ]
        )
        #expect(ledger.knownCategoryNames == ["餐饮", "交通", "自定义"])
    }

    @Test func mergeKeepsLocalCategoryOrderAndAppendsRemote() {
        let dining = LedgerCategory(name: "餐饮", symbolName: "fork.knife", kind: .expense)
        let transit = LedgerCategory(name: "交通", symbolName: "car.fill", kind: .expense)
        let shopping = LedgerCategory(name: "购物", symbolName: "bag.fill", kind: .expense)

        let merged = Ledger.merged(
            local: Ledger(categories: [dining, transit]),
            remote: Ledger(categories: [shopping])
        )

        #expect(merged.categories.map(\.name) == ["餐饮", "交通", "购物"])
    }

    @Test func conflictMergeKeepsNewestUpdatedAt() {
        let id = UUID()
        let old = LedgerTransaction(id: id, amount: 10, merchant: "旧", updatedAt: Date(timeIntervalSince1970: 1))
        let newest = LedgerTransaction(id: id, amount: 20, merchant: "新", updatedAt: Date(timeIntervalSince1970: 2))
        let unique = LedgerTransaction(amount: 30, merchant: "仅远端")
        let merged = Ledger.merged(
            local: Ledger(transactions: [old]),
            remote: Ledger(transactions: [newest, unique])
        )
        #expect(merged.transactions.count == 2)
        #expect(merged.transactions.first(where: { $0.id == id })?.merchant == "新")
    }

    @Test func duplicateDetection() {
        let date = Date()
        let existing = LedgerTransaction(amount: 28.5, currency: .CNY, merchant: "咖啡", date: date)
        let candidate = LedgerTransaction(amount: 28.5, currency: .CNY, merchant: "咖啡", date: date.addingTimeInterval(60))
        #expect(Ledger(transactions: [existing]).isDuplicate(candidate))
    }

    @Test func typicalOCRRuleSample() async throws {
        let text = """
        微信支付
        瑞幸咖啡
        交易时间 2026年11月13日 09:42
        原价 ¥35.00
        优惠 ¥6.50
        实付 ¥28.50
        订单号 123456789012
        """
        let result = try await RuleBasedTransactionParser().parse(text: text, defaultCurrency: .USD)
        #expect(result.transaction.amount == Decimal(string: "28.50"))
        #expect(result.transaction.currency == .CNY)
        #expect(result.transaction.paymentMethod == "微信支付")
        #expect(result.transaction.category == "餐饮")
    }

    @Test func unavailableFoundationModelFallsBackToRules() async throws {
        let parser = FallbackTransactionParser(primary: nil)
        let result = try await parser.parse(text: "支付宝\n实付 CNY 18.80", defaultCurrency: .USD)
        #expect(result.source == "本地规则")
        #expect(result.transaction.amount == Decimal(string: "18.80"))
        #expect(result.transaction.currency == .CNY)
    }

    @Test func csvExportEscapesFields() {
        let item = LedgerTransaction(amount: 12.99, currency: .USD, merchant: "Shop, Inc.", note: "line1\nline2")
        let text = String(decoding: CSVExporter().data(for: Ledger(transactions: [item])), as: UTF8.self)
        #expect(text.contains(#""Shop, Inc.""#))
        #expect(text.contains("\"line1\nline2\""))
        #expect(text.contains(",12.99,USD,"))
    }
}
