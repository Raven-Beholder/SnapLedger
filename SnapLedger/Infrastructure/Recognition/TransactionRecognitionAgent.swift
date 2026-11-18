import Foundation

struct TransactionRecognitionContext: Sendable {
    let defaultCurrency: Currency
    let categoryNames: [String]
    let paymentMethodNames: [String]
    let recognitionGuidance: String
}

struct TransactionRecognitionAgent: Sendable {
    typealias EventSink = @Sendable (String) async -> Void

    private let ocr = OCRService()
    private let parser = FoundationModelTransactionParser()

    func run(
        imageData: Data,
        context: TransactionRecognitionContext,
        eventSink: @escaping EventSink
    ) async throws -> ParsedTransaction {
        await eventSink("Agent：开始分析图片")

        let ocrStartedAt = Date()
        await eventSink("Agent：运行多语言 Vision OCR 预处理")
        let preparedOCR = try await ocr.prepareForModel(data: imageData)
        let ocrDuration = Date().timeIntervalSince(ocrStartedAt)
        let lineCount = preparedOCR.text.split(whereSeparator: \.isNewline).count
        let retryDescription = preparedOCR.retryPassCount > 0
            ? "，含 \(preparedOCR.retryPassCount) 次语言定向复核"
            : ""
        await eventSink(
            "Agent：OCR 完成（\(lineCount) 行，\(preparedOCR.text.count) 字符，\(formatted(ocrDuration)) 秒\(retryDescription)）"
        )
        if !preparedOCR.excludedStatusBarLines.isEmpty {
            await eventSink(
                "Agent：已排除状态栏文字：\(preparedOCR.excludedStatusBarLines.joined(separator: "、"))"
            )
        }

        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            do {
                await eventSink("Agent：将图片与 OCR 文本交给 VLM 融合解析")
                var parsed = try await parser.parse(
                    imageData: imageData,
                    ocrText: preparedOCR.text,
                    defaultCurrency: context.defaultCurrency,
                    categoryNames: context.categoryNames,
                    paymentMethodNames: context.paymentMethodNames,
                    recognitionGuidance: context.recognitionGuidance
                )
                parsed.ocrText = preparedOCR.text
                parsed.excludedStatusBarLines = preparedOCR.excludedStatusBarLines
                await eventSink("Agent：VLM 融合解析完成")
                return parsed
            } catch {
                let nsError = error as NSError
                await eventSink(
                    "Agent：VLM 失败，转入 OCR 文本回退（\(nsError.domain) · \(nsError.code)）"
                )
            }
        }
        #endif

        await eventSink("Agent：使用 OCR 文本生成结构化交易")
        var parsed = try await parser.parse(
            text: preparedOCR.text,
            defaultCurrency: context.defaultCurrency,
            categoryNames: context.categoryNames,
            paymentMethodNames: context.paymentMethodNames,
            recognitionGuidance: context.recognitionGuidance
        )
        parsed.ocrText = preparedOCR.text
        parsed.excludedStatusBarLines = preparedOCR.excludedStatusBarLines
        await eventSink("Agent：OCR 文本回退完成")
        return parsed
    }

    private func formatted(_ duration: TimeInterval) -> String {
        duration.formatted(.number.precision(.fractionLength(2)))
    }
}
