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
