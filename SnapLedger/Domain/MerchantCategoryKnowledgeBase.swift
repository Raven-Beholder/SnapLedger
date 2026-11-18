import Foundation

/// The single source of truth for built-in merchant and transaction category knowledge.
enum MerchantCategoryKnowledgeBase {
    private struct Rule: Sendable {
        let pattern: String
        let category: String
    }

    // Keep more specific aliases before their prefixes (for example Uber Eats before Uber).
    private static let merchantRules: [Rule] = [
        Rule(pattern: "ubereats", category: "餐饮"),
        Rule(pattern: "mcdonalds", category: "餐饮"),
        Rule(pattern: "mcdonald", category: "餐饮"),
        Rule(pattern: "麦当劳", category: "餐饮"),
        Rule(pattern: "starbucks", category: "餐饮"),
        Rule(pattern: "星巴克", category: "餐饮"),
        Rule(pattern: "foodpanda", category: "餐饮"),
        Rule(pattern: "deliveroo", category: "餐饮"),
        Rule(pattern: "美团外卖", category: "餐饮"),
        Rule(pattern: "饿了么", category: "餐饮"),
        Rule(pattern: "keeta", category: "餐饮"),
        Rule(pattern: "uber", category: "交通"),
        Rule(pattern: "grab", category: "交通"),
        Rule(pattern: "滴滴", category: "交通")
    ]

    private static let transactionTextRules: [Rule] = [
        Rule(pattern: "咖啡", category: "餐饮"),
        Rule(pattern: "餐", category: "餐饮"),
        Rule(pattern: "打车", category: "交通"),
        Rule(pattern: "地铁", category: "交通"),
        Rule(pattern: "酒店", category: "旅行"),
        Rule(pattern: "超市", category: "购物"),
        Rule(pattern: "退款", category: "退款")
    ]

    static func trustedCategory(forMerchant merchant: String) -> String? {
        category(matching: normalize(merchant), rules: merchantRules)
    }

    static func inferredCategory(inTransactionText text: String) -> String? {
        trustedCategory(forMerchant: text)
            ?? category(matching: normalize(text), rules: transactionTextRules)
    }

    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func category(matching normalizedText: String, rules: [Rule]) -> String? {
        rules.first { normalizedText.contains($0.pattern) }?.category
    }
}
