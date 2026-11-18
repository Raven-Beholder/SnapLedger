import Foundation

struct TransactionRecognitionContext: Sendable {
    let defaultCurrency: Currency
    let categoryNames: [String]
    let paymentMethodNames: [String]
    let recognitionGuidance: String
}

enum TransactionRecognitionEvent: Sendable {
    case started
    case ocrStarted
    case ocrCompleted(lineCount: Int, characterCount: Int, duration: TimeInterval, retryPassCount: Int)
    case excludedStatusBarLines([String])
    case multimodalStarted
    case multimodalFallback(errorDomain: String, errorCode: Int)
    case textFallbackStarted
    case completed(source: String)

    var message: String {
        switch self {
        case .started:
            "Agent：开始分析图片"
        case .ocrStarted:
            "Agent：运行多语言 Vision OCR 预处理"
        case let .ocrCompleted(lineCount, characterCount, duration, retryPassCount):
            "Agent：OCR 完成（\(lineCount) 行，\(characterCount) 字符，\(duration.formatted(.number.precision(.fractionLength(2)))) 秒\(retryPassCount > 0 ? "，含 \(retryPassCount) 次语言定向复核" : "")）"
        case let .excludedStatusBarLines(lines):
            "Agent：已排除状态栏文字：\(lines.joined(separator: "、"))"
        case .multimodalStarted:
            "Agent：将图片与 OCR 文本交给 VLM 融合解析"
        case let .multimodalFallback(errorDomain, errorCode):
            "Agent：VLM 失败，转入 OCR 文本回退（\(errorDomain) · \(errorCode)）"
        case .textFallbackStarted:
            "Agent：使用 OCR 文本生成结构化交易"
        case let .completed(source):
            "Agent：识别完成（\(source)）"
        }
    }
}

struct TransactionRecognitionAgent: Sendable {
    typealias EventSink = @Sendable (TransactionRecognitionEvent) async -> Void

    private let ocr = OCRService()
    private let parser = FoundationModelTransactionParser()

    func run(
        imageData: Data,
        context: TransactionRecognitionContext,
        eventSink: @escaping EventSink
    ) async throws -> ParsedTransaction {
        await eventSink(.started)

        let ocrStartedAt = Date()
        await eventSink(.ocrStarted)
        let preparedOCR = try await ocr.prepareForModel(data: imageData)
        try Task.checkCancellation()
        let ocrDuration = Date().timeIntervalSince(ocrStartedAt)
        let lineCount = preparedOCR.text.split(whereSeparator: \.isNewline).count
        await eventSink(
            .ocrCompleted(
                lineCount: lineCount,
                characterCount: preparedOCR.text.count,
                duration: ocrDuration,
                retryPassCount: preparedOCR.retryPassCount
            )
        )
        if !preparedOCR.excludedStatusBarLines.isEmpty {
            await eventSink(.excludedStatusBarLines(preparedOCR.excludedStatusBarLines))
        }

        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            do {
                await eventSink(.multimodalStarted)
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
                await eventSink(.completed(source: parsed.source))
                return parsed
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                await eventSink(.multimodalFallback(errorDomain: nsError.domain, errorCode: nsError.code))
            }
        }
        #endif

        await eventSink(.textFallbackStarted)
        var parsed = try await parser.parse(
            text: preparedOCR.text,
            defaultCurrency: context.defaultCurrency,
            categoryNames: context.categoryNames,
            paymentMethodNames: context.paymentMethodNames,
            recognitionGuidance: context.recognitionGuidance
        )
        parsed.ocrText = preparedOCR.text
        parsed.excludedStatusBarLines = preparedOCR.excludedStatusBarLines
        await eventSink(.completed(source: parsed.source))
        return parsed
    }

    private func formatted(_ duration: TimeInterval) -> String {
        duration.formatted(.number.precision(.fractionLength(2)))
    }
}
