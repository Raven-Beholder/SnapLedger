import Foundation

enum DecimalCoding {
    static func string(from value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func decimal(from text: String) -> Decimal? {
        var normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("+") { normalized.removeFirst() }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func decode<K: CodingKey>(
        from container: KeyedDecodingContainer<K>, forKey key: K
    ) throws -> Decimal {
        let text = try container.decode(String.self, forKey: key)
        guard let value = decimal(from: text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container, debugDescription: "金额必须是十进制字符串"
            )
        }
        return value
    }

    static func encode<K: CodingKey>(
        _ value: Decimal, to container: inout KeyedEncodingContainer<K>, forKey key: K
    ) throws {
        try container.encode(string(from: value), forKey: key)
    }
}

enum LedgerCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum DateParsing {
    static func parse(_ text: String, now: Date = .now) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let formats = [
            "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm",
            "yyyy年M月d日", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd", "MM月dd日 HH:mm", "M月d日 HH:mm"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                if format.hasPrefix("M") {
                    let year = Calendar.current.component(.year, from: now)
                    return Calendar.current.date(bySetting: .year, value: year, of: date)
                }
                return date
            }
        }
        return nil
    }
}

enum UserFacingError: LocalizedError {
    case noText, missingAmount, invalidAmount, invalidLedger, permissionLost
    case conflict, unsupportedImage, cancelled, modelUnavailable, message(String)

    var errorDescription: String? {
        switch self {
        case .noText: "没有识别到文字，请换一张清晰的截图或手动填写。"
        case .missingAmount: "未找到实际支付金额，请手动填写。"
        case .invalidAmount: "金额格式无效，必须是大于零的十进制数。"
        case .invalidLedger: "账本文件已损坏或不是受支持的 ledger.json。"
        case .permissionLost: "账本文件访问权限已失效，请重新选择文件。"
        case .conflict: "检测到其他设备更新，已合并较新的交易，请再次确认保存。"
        case .unsupportedImage: "无法读取所选图片。"
        case .cancelled: "操作已取消。"
        case .modelUnavailable: "Apple 智能模型当前不可用，已使用本地规则解析。"
        case .message(let text): text
        }
    }
}
