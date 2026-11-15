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
    enum Precision: Equatable, Sendable {
        case dateAndTime
        case dateOnly
        case missingYear
        case relativeDate
        case timeOnly

        var requiresConfirmation: Bool { self != .dateAndTime }
    }

    struct Resolution: Equatable, Sendable {
        let date: Date
        let precision: Precision
        let sourceText: String

        var requiresConfirmation: Bool { precision.requiresConfirmation }
    }

    static func parse(_ text: String, now: Date = .now) -> Date? {
        resolve(text, now: now)?.date
    }

    static func resolve(_ text: String, now: Date = .now) -> Resolution? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) {
            return Resolution(date: date, precision: .dateAndTime, sourceText: trimmed)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) {
            return Resolution(date: date, precision: .dateAndTime, sourceText: trimmed)
        }

        let dateTimeFormats = [
            "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy/M/d HH:mm:ss", "yyyy/M/d HH:mm",
            "yyyy.M.d HH:mm:ss", "yyyy.M.d HH:mm"
        ]
        if let date = firstDate(in: trimmed, formats: dateTimeFormats) {
            return Resolution(date: date, precision: .dateAndTime, sourceText: trimmed)
        }

        let dateOnlyFormats = ["yyyy年M月d日", "yyyy-MM-dd", "yyyy/M/d", "yyyy.M.d"]
        if let date = firstDate(in: trimmed, formats: dateOnlyFormats) {
            return Resolution(date: date, precision: .dateOnly, sourceText: trimmed)
        }

        if let components = partialDateComponents(from: trimmed),
           let date = closestNonFutureDate(components, now: now) {
            return Resolution(date: date, precision: .missingYear, sourceText: trimmed)
        }

        if let relative = relativeDate(from: trimmed, now: now) {
            return Resolution(date: relative, precision: .relativeDate, sourceText: trimmed)
        }

        if trimmed.range(of: #"^\d{1,2}:\d{2}(?::\d{2})?$"#, options: .regularExpression) != nil,
           let time = timeComponents(from: trimmed),
           let date = dateForTime(time, now: now) {
            return Resolution(date: date, precision: .timeOnly, sourceText: trimmed)
        }
        return nil
    }

    static func firstResolution(in text: String, now: Date = .now) -> Resolution? {
        let normalized = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let patterns = [
            #"\d{4}年\d{1,2}月\d{1,2}日(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?"#,
            #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(?:[T\s]\d{1,2}:\d{2}(?::\d{2})?(?:[+-]\d{2}:\d{2}|Z)?)?"#,
            #"\d{1,2}月\d{1,2}日(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?"#,
            #"\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?"#,
            #"(?:今天|今日|昨天|昨日)\s*\d{1,2}:\d{2}(?::\d{2})?"#
        ]
        for pattern in patterns {
            guard let range = normalized.range(of: pattern, options: .regularExpression) else { continue }
            if let result = resolve(String(normalized[range]), now: now) { return result }
        }
        return nil
    }

    private static func firstDate(in text: String, formats: [String]) -> Date? {
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.isLenient = false
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func partialDateComponents(from text: String) -> DateComponents? {
        let patterns = [
            #"^(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$"#,
            #"^(\d{1,2})[-/](\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$"#
        ]
        for pattern in patterns {
            guard let values = captures(pattern, in: text), values.count >= 2 else { continue }
            var result = DateComponents()
            result.month = Int(values[0])
            result.day = Int(values[1])
            if values.count > 2 { result.hour = Int(values[2]) }
            if values.count > 3 { result.minute = Int(values[3]) }
            if values.count > 4 { result.second = Int(values[4]) }
            return result
        }
        return nil
    }

    private static func closestNonFutureDate(_ components: DateComponents, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard valid(components) else { return nil }
        var candidate = components
        candidate.year = calendar.component(.year, from: now)
        guard var date = calendar.date(from: candidate) else { return nil }
        guard calendar.component(.month, from: date) == components.month,
              calendar.component(.day, from: date) == components.day else { return nil }
        if date > now.addingTimeInterval(5 * 60) {
            candidate.year = (candidate.year ?? 0) - 1
            guard let previousYear = calendar.date(from: candidate) else { return nil }
            date = previousYear
        }
        return date
    }

    private static func relativeDate(from text: String, now: Date) -> Date? {
        guard text.hasPrefix("今天") || text.hasPrefix("今日") ||
              text.hasPrefix("昨天") || text.hasPrefix("昨日") else { return nil }
        guard let time = timeComponents(from: text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dayOffset = (text.hasPrefix("昨天") || text.hasPrefix("昨日")) ? -1 : 0
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { return nil }
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: day)
    }

    private static func timeComponents(from text: String) -> DateComponents? {
        guard let values = captures(#"(\d{1,2}):(\d{2})(?::(\d{2}))?$"#, in: text),
              values.count >= 2 else { return nil }
        let result = DateComponents(hour: Int(values[0]), minute: Int(values[1]),
                                    second: values.count > 2 ? Int(values[2]) : 0)
        return valid(result) ? result : nil
    }

    private static func dateForTime(_ time: DateComponents, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard var date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                       second: time.second ?? 0, of: now) else { return nil }
        if date > now.addingTimeInterval(5 * 60) {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return date
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func valid(_ components: DateComponents) -> Bool {
        if let month = components.month, !(1...12).contains(month) { return false }
        if let day = components.day, !(1...31).contains(day) { return false }
        if let hour = components.hour, !(0...23).contains(hour) { return false }
        if let minute = components.minute, !(0...59).contains(minute) { return false }
        if let second = components.second, !(0...59).contains(second) { return false }
        return true
    }
}

enum UserFacingError: LocalizedError {
    case noText, missingAmount, invalidAmount, invalidLedger, ledgerMissing, permissionLost
    case conflict, unsupportedImage, cancelled, modelUnavailable, message(String)

    var errorDescription: String? {
        switch self {
        case .noText: "没有识别到文字，请换一张清晰的截图或手动填写。"
        case .missingAmount: "未找到实际支付金额，请手动填写。"
        case .invalidAmount: "金额格式无效，必须是大于零的十进制数。"
        case .invalidLedger: "账本文件已损坏或不是受支持的 ledger.json。"
        case .ledgerMissing: "上次使用的账本已被移动或删除，请重新选择 ledger.json。"
        case .permissionLost: "账本文件访问权限已失效，请重新选择文件。"
        case .conflict: "检测到其他设备更新，已合并较新的交易，请再次确认保存。"
        case .unsupportedImage: "无法读取所选图片。"
        case .cancelled: "操作已取消。"
        case .modelUnavailable: "Apple 智能模型当前不可用，已使用本地规则解析。"
        case .message(let text): text
        }
    }
}
