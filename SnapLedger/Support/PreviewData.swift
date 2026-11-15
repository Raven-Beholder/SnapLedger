import Foundation

#if DEBUG
enum PreviewData {
    static let ledger = Ledger(
        defaultCurrency: .CNY,
        transactions: transactions,
        categories: categories,
        recognitionGuidance: "优先识别实付金额；外卖平台统一归类为餐饮；打车平台统一归类为交通。"
    )

    @MainActor
    static func appModel() -> AppModel {
        let model = AppModel()
        model.ledger = ledger
        model.defaultCurrency = ledger.defaultCurrency
        model.foundationModelStatus = "可用（Preview 模拟状态）"
        model.analysisPhase = "等待导入"
        return model
    }

    private static let categories: [LedgerCategory] = [
        .init(name: "餐饮", symbolName: "fork.knife", kind: .expense),
        .init(name: "交通", symbolName: "car.fill", kind: .expense),
        .init(name: "购物", symbolName: "bag.fill", kind: .expense),
        .init(name: "居住", symbolName: "house.fill", kind: .expense),
        .init(name: "旅行", symbolName: "airplane", kind: .expense),
        .init(name: "医疗", symbolName: "cross.case.fill", kind: .expense),
        .init(name: "娱乐", symbolName: "gamecontroller.fill", kind: .expense),
        .init(name: "教育", symbolName: "book.fill", kind: .expense),
        .init(name: "订阅服务", symbolName: "repeat.circle.fill", kind: .expense),
        .init(name: "账户互转", symbolName: "arrow.left.arrow.right", kind: .expense),
        .init(name: "工资", symbolName: "banknote.fill", kind: .income),
        .init(name: "奖金", symbolName: "gift.fill", kind: .income),
        .init(name: "投资收益", symbolName: "chart.line.uptrend.xyaxis", kind: .income),
        .init(name: "其他收入", symbolName: "plus.circle.fill", kind: .income),
        .init(name: "旧分类", symbolName: "archivebox.fill", kind: .expense, isArchived: true)
    ]

    private static let transactions: [LedgerTransaction] = [
        transaction(.expense, 28.50, .CNY, "瑞幸咖啡", "餐饮", 2026, 11, 15, 9, 18, "微信支付", "早餐咖啡"),
        transaction(.expense, 86.40, .CNY, "盒马鲜生", "购物", 2026, 11, 14, 19, 42, "支付宝", "周末采购"),
        transaction(.expense, 42.00, .CNY, "滴滴出行", "交通", 2026, 11, 13, 22, 8, "微信支付"),
        transaction(.refund, 19.90, .CNY, "美团外卖", "餐饮", 2026, 11, 12, 14, 25, "支付宝", "缺货退款"),
        transaction(.expense, 128.00, .HKD, "MTR Mobile", "交通", 2026, 11, 10, 8, 5, "Visa"),
        transaction(.expense, 12.99, .USD, "Apple", "订阅服务", 2026, 11, 8, 10, 0, "Apple Pay", "iCloud+ 月度订阅"),
        transaction(.income, 28_600, .CNY, "星河科技有限公司", "工资", 2026, 11, 5, 9, 0, "银行转账", "十一月工资"),
        transaction(.expense, 2_980, .CNY, "自如", "居住", 2026, 11, 3, 8, 30, "银行卡", "十一月房租"),
        transaction(.transfer, 5_000, .CNY, "招商银行 → 支付宝", "账户互转", 2026, 11, 1, 12, 0, "银行转账"),
        transaction(.expense, 368.00, .CNY, "上海迪士尼度假区", "娱乐", 2026, 10, 28, 11, 35, "Apple Pay"),
        transaction(.expense, 1_260, .HKD, "Hong Kong Airlines", "旅行", 2026, 10, 22, 16, 20, "Mastercard", "香港往返机票"),
        transaction(.expense, 239.00, .CNY, "京东", "购物", 2026, 10, 18, 20, 11, "京东支付", "机械键盘"),
        transaction(.expense, 49.00, .CNY, "得到 App", "教育", 2026, 10, 12, 7, 45, "微信支付"),
        transaction(.income, 3_280.75, .CNY, "证券账户", "投资收益", 2026, 10, 9, 15, 1, "银行转账", "基金赎回收益"),
        transaction(.expense, 320.00, .CNY, "瑞金医院", "医疗", 2026, 10, 6, 10, 32, "医保电子凭证"),
        transaction(.income, 8_000, .CNY, "星河科技有限公司", "奖金", 2026, 9, 30, 18, 0, "银行转账", "季度绩效奖金"),
        transaction(.expense, 9.80, .CNY, "上海地铁", "交通", 2026, 9, 27, 8, 12, "交通卡"),
        transaction(.expense, 156.60, .CNY, "海底捞", "餐饮", 2026, 9, 20, 20, 18, "微信支付", "朋友聚餐"),
        transaction(.expense, 79.99, .USD, "GitHub", "订阅服务", 2026, 9, 15, 12, 0, "Visa", "Copilot 年度折扣"),
        transaction(.income, 1_200, .HKD, "自由职业项目", "其他收入", 2026, 9, 8, 17, 30, "转数快", "设计咨询")
    ]

    private static func transaction(
        _ type: TransactionType,
        _ amount: Decimal,
        _ currency: Currency,
        _ merchant: String,
        _ category: String,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ paymentMethod: String? = nil,
        _ note: String? = nil
    ) -> LedgerTransaction {
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "Asia/Shanghai"),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date ?? .now

        return LedgerTransaction(
            type: type,
            amount: amount,
            currency: currency,
            merchant: merchant,
            category: category,
            date: date,
            paymentMethod: paymentMethod,
            note: note,
            createdAt: date,
            updatedAt: date
        )
    }
}
#endif
