import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct ImportView: View {
    let model: AppModel
    @State private var isShowingDiagnostics = false
    #if os(iOS)
    @State private var photoItems: [PhotosPickerItem] = []
    #else
    @State private var isChoosingImages = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                importActions
                status

            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("导入截图")
        .toolbar {
            if model.analysisStartedAt != nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button("模型诊断", systemImage: "waveform.path.ecg") {
                        isShowingDiagnostics = true
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            ModelDiagnosticsView(model: model)
        }
        #if os(macOS)
        .fileImporter(
            isPresented: $isChoosingImages,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let images = urls.compactMap(loadImageData)
                if !images.isEmpty { model.importImages(images) }
            case .failure(let error):
                model.present(error)
            }
        }
        #endif
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("从截图自动记账")
                    .font(.title2.weight(.semibold))
                Text("选择支付截图，设备端模型会提取金额、商户与分类，保存前由你确认。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
    }

    @ViewBuilder
    private var importActions: some View {
        #if os(iOS)
        PhotosPicker(
            selection: $photoItems,
            maxSelectionCount: 20,
            selectionBehavior: .ordered,
            matching: .images
        ) {
            Label("选择支付截图", systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .onChange(of: photoItems) { _, items in
            Task {
                var images: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        images.append(data)
                    }
                }
                photoItems.removeAll()
                if !images.isEmpty { model.importImages(images) }
            }
        }
        #else
        VStack(spacing: 16) {
            Button {
                isChoosingImages = true
            } label: {
                Label("从文件选择图片", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            dropTarget
        }
        #endif
    }

    #if os(macOS)
    private func loadImageData(from url: URL) -> Data? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? Data(contentsOf: url)
    }

    private var dropTarget: some View {
        Text("也可以把图片拖到这里")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            }
            .dropDestination(for: URL.self) { urls, _ in
                let data = urls.filter { $0.isFileURL }.compactMap { try? Data(contentsOf: $0) }
                if !data.isEmpty { model.importImages(data) }
                return !data.isEmpty
            }
    }
    #endif

    @ViewBuilder
    private var status: some View {
        switch model.importState {
        case .idle:
            Label("截图仅用于本次设备端识别，不会上传或保存。", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .processing(let current, let total):
            VStack(spacing: 14) {
                ProgressView(value: Double(current), total: Double(max(total, 1))) {
                    Text("正在识别 \(current)/\(total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                Button("取消导入", role: .cancel) { model.cancelImport() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
            .frame(maxWidth: 320)
        case .reviewing:
            ReviewQueueView(model: model)
        }
    }
}

#if DEBUG
#Preview("截图导入") {
    @Previewable @State var model = PreviewData.appModel()
    NavigationStack {
        ImportView(model: model)
    }
}
#endif

private struct ModelDiagnosticsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                LabeledContent("当前阶段", value: model.analysisPhase)
                if let startedAt = model.analysisStartedAt, let endedAt = model.analysisEndedAt {
                    LabeledContent(
                        "总耗时",
                        value: endedAt.timeIntervalSince(startedAt).formatted(.number.precision(.fractionLength(1))) + " 秒"
                    )
                } else if let startedAt = model.analysisStartedAt {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        LabeledContent(
                            "总耗时",
                            value: context.date.timeIntervalSince(startedAt).formatted(.number.precision(.fractionLength(1))) + " 秒"
                        )
                    }
                }
                if let metrics = model.lastGenerationMetrics {
                    LabeledContent("输入 token", value: "\(metrics.inputTokens)")
                    LabeledContent("输出 token", value: "\(metrics.outputTokens)")
                    LabeledContent("Reasoning token", value: "\(metrics.reasoningTokens)")
                    LabeledContent(
                        "平均生成速度",
                        value: metrics.tokensPerSecond.formatted(.number.precision(.fractionLength(1))) + " token/s"
                    )
                }
                if !model.lastOCRText.isEmpty {
                    OCRDiagnosticsSection(
                        text: model.lastOCRText,
                        excludedStatusBarLines: model.lastExcludedStatusBarLines
                    )
                }
                if !model.lastStructuredOutput.isEmpty {
                    Text("模型结构化输出")
                        .font(.headline)
                    Text(model.lastStructuredOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                if !model.analysisEvents.isEmpty {
                    PipelineTimelineView(
                        events: model.analysisEvents,
                        startDate: model.analysisStartedAt
                    )
                }
                Text("仅显示模型返回的字段和公开 usage 数据，不展示或保存私有思维链。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("模型诊断")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct OCRDiagnosticsSection: View {
    let text: String
    let excludedStatusBarLines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vision OCR 结果")
                .font(.headline)

            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if !excludedStatusBarLines.isEmpty {
                LabeledContent("已过滤状态栏") {
                    Text(excludedStatusBarLines.formatted())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PipelineTimelineView: View {
    let events: [AnalysisTimelineEvent]
    let startDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pipeline 时间轴")
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(events.enumerated(), id: \.element.id) { index, event in
                    PipelineTimelineRow(
                        event: event,
                        startDate: startDate,
                        isLast: index == events.count - 1
                    )
                }
            }
        }
    }
}

private struct PipelineTimelineRow: View {
    let event: AnalysisTimelineEvent
    let startDate: Date?
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(elapsedText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            VStack(spacing: 0) {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(eventColor)
                    .frame(width: 18, height: 18)
                    .background(eventColor.opacity(0.14), in: Circle())

                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
        .frame(minHeight: isLast ? 24 : 52, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private var elapsedText: String {
        guard let startDate else { return "—" }
        let elapsed = max(0, event.timestamp.timeIntervalSince(startDate))
        return "+" + elapsed.formatted(.number.precision(.fractionLength(1))) + "s"
    }

    private var eventColor: Color {
        switch event.kind {
        case .phase:
            .secondary
        case .tool:
            .blue
        case .success:
            .green
        case .failure:
            .red
        }
    }

    private var symbolName: String {
        switch event.kind {
        case .phase:
            "circle.fill"
        case .tool:
            "wrench.and.screwdriver.fill"
        case .success:
            "checkmark"
        case .failure:
            "exclamationmark"
        }
    }
}

struct ReviewQueueView: View {
    let model: AppModel

    var body: some View {
        GroupBox {
            VStack(spacing: 14) {
                if let candidate = model.pendingTransactions.first {
                    VStack(spacing: 4) {
                        Text("待确认 \(model.pendingTransactions.count) 张截图")
                            .font(.headline)
                        Text("解析方式：\(candidate.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("确认下一笔交易") {
                        model.review(candidate)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("没有待确认的截图")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button("取消全部", role: .cancel) { model.cancelImport() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        } label: {
            Label("待确认截图", systemImage: "tray.full")
        }
        .frame(maxWidth: 420)
    }
}

struct ConfirmationView: View {
    @State private var draft: LedgerTransaction
    @State private var amountText: String
    @State private var merchantText: String
    @State private var categoryText: String
    @State private var paymentMethodText: String
    @State private var noteText: String
    @State private var isShowingDiagnostics = false
    let lowConfidenceFields: Set<String>
    let parserSource: String
    let dateSourceText: String?
    let sourceImageData: Data?
    let generationMetrics: GenerationMetrics?
    let structuredOutput: String?
    let availableCategories: [String]
    let availablePaymentMethods: [String]
    let canDiscard: Bool
    let onSave: (LedgerTransaction) -> Void
    let onDiscard: () -> Void
    let onCancel: () -> Void
    @State private var validationMessage: String?

    init(
        transaction: LedgerTransaction,
        lowConfidenceFields: Set<String>,
        parserSource: String,
        dateSourceText: String?,
        sourceImageData: Data?,
        generationMetrics: GenerationMetrics?,
        structuredOutput: String?,
        availableCategories: [String],
        availablePaymentMethods: [String],
        canDiscard: Bool,
        onSave: @escaping (LedgerTransaction) -> Void,
        onDiscard: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: transaction)
        _amountText = State(initialValue: DecimalCoding.string(from: transaction.amount))
        _merchantText = State(initialValue: transaction.merchant)
        _categoryText = State(initialValue: transaction.category)
        _paymentMethodText = State(initialValue: transaction.paymentMethod ?? "")
        _noteText = State(initialValue: transaction.note ?? "")
        self.lowConfidenceFields = lowConfidenceFields
        self.parserSource = parserSource
        self.dateSourceText = dateSourceText
        self.sourceImageData = sourceImageData
        self.generationMetrics = generationMetrics
        self.structuredOutput = structuredOutput
        self.availableCategories = availableCategories
        self.availablePaymentMethods = availablePaymentMethods
        self.canDiscard = canDiscard
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sourceImageData {
                    Section {
                        SourceImagePreview(imageData: sourceImageData)
                    } header: {
                        Text("本次识别图片")
                    } footer: {
                        Text("图片仅保留在待确认队列的内存中，不会写入账本或磁盘。")
                    }
                }
                Section {
                    LabeledContent("解析方式", value: parserSource)
                    if !lowConfidenceFields.isEmpty {
                        Label("标记为“请确认”的字段需要人工核对", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if generationMetrics != nil || structuredOutput != nil {
                    Section {
                        Button("查看本张图片的模型诊断", systemImage: "waveform.path.ecg") {
                            isShowingDiagnostics = true
                        }
                    }
                }

                Section("交易信息") {
                    Picker(fieldLabel("类型", key: "type"), selection: $draft.type) {
                        ForEach(TransactionType.allCases) { Text($0.displayName).tag($0) }
                    }
                    LabeledContent(fieldLabel("金额", key: "amount")) {
                        TextField(text: $amountText, prompt: Text("0.00")) {
                            Text("金额输入")
                        }
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    Picker(fieldLabel("币种", key: "currency"), selection: $draft.currency) {
                        ForEach(Currency.allCases) { Text("\($0.rawValue) · \($0.displayName)").tag($0) }
                    }
                    LabeledContent(fieldLabel("商户", key: "merchant")) {
                        IMESafeTextField("必填", text: $merchantText)
                    }
                    CategoryEditor(
                        category: $categoryText,
                        availableCategories: availableCategories,
                        label: fieldLabel("分类", key: "category")
                    )
                }

                Section("时间与补充信息") {
                    TransactionDateEditor(
                        date: $draft.date,
                        requiresReview: lowConfidenceFields.contains("date"),
                        sourceText: dateSourceText
                    )
                    PaymentMethodEditor(
                        paymentMethod: $paymentMethodText,
                        availablePaymentMethods: availablePaymentMethods,
                        label: fieldLabel("支付方式", key: "paymentMethod")
                    )
                    LabeledContent(fieldLabel("备注", key: "note")) {
                        IMESafeTextField("选填", text: $noteText)
                    }
                }
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
                if canDiscard {
                    Section {
                        Button("丢弃此张截图", role: .destructive, action: onDiscard)
                    } footer: {
                        Text("不会写入账本；如果队列中还有截图，会自动进入下一张。")
                    }
                }
            }
            #if os(macOS)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
            #endif
            .navigationTitle("确认交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("写入账本") {
                        guard let amount = DecimalCoding.decimal(from: amountText), amount > 0 else {
                            validationMessage = UserFacingError.invalidAmount.errorDescription
                            return
                        }
                        let merchant = merchantText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !merchant.isEmpty else {
                            validationMessage = "请填写商户。"
                            return
                        }
                        draft.amount = amount
                        draft.merchant = merchant
                        draft.category = categoryText.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.paymentMethod = nilIfEmpty(paymentMethodText)
                        draft.note = nilIfEmpty(noteText)
                        onSave(draft)
                    }
                }
            }
            .sheet(isPresented: $isShowingDiagnostics) {
                CandidateModelDiagnosticsView(
                    metrics: generationMetrics,
                    structuredOutput: structuredOutput
                )
            }
        }
        #if os(macOS)
        .frame(width: 760, height: 680)
        .formStyle(.grouped)
        .presentationSizing(.fitted)
        #endif
    }

    private func fieldLabel(_ title: String, key: String) -> String {
        lowConfidenceFields.contains(key) ? "\(title)（请确认）" : title
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PaymentMethodEditor: View {
    @Binding var paymentMethod: String
    let availablePaymentMethods: [String]
    let label: String
    @State private var isAddingPaymentMethod = false

    private var menuMethods: [String] {
        let trimmed = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !availablePaymentMethods.contains(where: {
                  $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }) else {
            return availablePaymentMethods
        }
        return [trimmed] + availablePaymentMethods
    }

    var body: some View {
        LabeledContent(label) {
            Menu {
                Button {
                    paymentMethod = ""
                } label: {
                    PaymentMethodMenuLabel(title: "未指定", isSelected: paymentMethod.isEmpty)
                }
                ForEach(menuMethods, id: \.self) { method in
                    Button {
                        paymentMethod = method
                    } label: {
                        PaymentMethodMenuLabel(
                            title: method,
                            isSelected: paymentMethod == method
                        )
                    }
                }
                Divider()
                Button("新增或自定义…", systemImage: "plus") {
                    isAddingPaymentMethod = true
                }
            } label: {
                HStack(spacing: 6) {
                    Text(paymentMethod.isEmpty ? "未指定" : paymentMethod)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $isAddingPaymentMethod) {
            PaymentMethodCustomEntryView(initialValue: paymentMethod) { value in
                paymentMethod = value
            }
        }
    }
}

private struct PaymentMethodMenuLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }
}

private struct PaymentMethodCustomEntryView: View {
    @State private var value: String
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void

    init(initialValue: String, onSave: @escaping (String) -> Void) {
        _value = State(initialValue: initialValue)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                IMESafeTextField(
                    "例如：微信支付、Visa •••• 1234",
                    text: $value,
                    alignment: .leading
                )
            }
            .navigationTitle("新增或自定义支付方式")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(value.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct CandidateModelDiagnosticsView: View {
    let metrics: GenerationMetrics?
    let structuredOutput: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                if let metrics {
                    LabeledContent("输入 token", value: "\(metrics.inputTokens)")
                    LabeledContent("输出 token", value: "\(metrics.outputTokens)")
                    LabeledContent("Reasoning token", value: "\(metrics.reasoningTokens)")
                    LabeledContent(
                        "生成耗时",
                        value: metrics.duration.formatted(.number.precision(.fractionLength(1))) + " 秒"
                    )
                    LabeledContent(
                        "平均生成速度",
                        value: metrics.tokensPerSecond.formatted(.number.precision(.fractionLength(1))) + " token/s"
                    )
                }
                if let structuredOutput, !structuredOutput.isEmpty {
                    Text(structuredOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("本张图片的模型诊断")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct SourceImagePreview: View {
    let imageData: Data
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(image, scale: 1, label: Text("待确认的支付截图"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView("正在显示原图…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            image = await Task.detached(priority: .userInitiated) { [imageData] in
                guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }.value
        }
    }
}

private struct TransactionDateEditor: View {
    @Binding var date: Date
    let requiresReview: Bool
    let sourceText: String?
    @State private var isSelectingDate = false

    var body: some View {
        if requiresReview {
            DateReviewNotice(sourceText: sourceText)
        }

        Button {
            isSelectingDate = true
        } label: {
            LabeledContent("交易时间") {
                Text(date, format: .dateTime.year().month().day().hour().minute())
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isSelectingDate) {
            TransactionDateSelectionView(date: date) { selectedDate in
                date = selectedDate
            }
        }
    }
}

private struct TransactionDateSelectionView: View {
    @State private var draftDate: Date
    @State private var isSelectingYear = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    let onConfirm: (Date) -> Void

    init(date: Date, onConfirm: @escaping (Date) -> Void) {
        _draftDate = State(initialValue: date)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日期与时间") {
                    Button {
                        isSelectingYear = true
                    } label: {
                        LabeledContent("年份") {
                            HStack(spacing: 6) {
                                Text("\(calendar.component(.year, from: draftDate)) 年")
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    DatePicker("日期", selection: $draftDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)

                    DatePicker("时间", selection: $draftDate, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("日期与时间")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onConfirm(draftDate)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isSelectingYear) {
                YearSelectionView(selectedYear: calendar.component(.year, from: draftDate)) { year in
                    yearSelection.wrappedValue = year
                }
            }
        }
    }

    private var yearSelection: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: draftDate) },
            set: { newYear in
                var components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: draftDate
                )
                components.year = newYear
                components.day = min(components.day ?? 1, daysInMonth(year: newYear, month: components.month ?? 1))
                if let updatedDate = calendar.date(from: components) {
                    draftDate = updatedDate
                }
            }
        )
    }

    private func daysInMonth(year: Int, month: Int) -> Int {
        let components = DateComponents(year: year, month: month, day: 1)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }
}

private struct YearSelectionView: View {
    @State private var draftYear: Int
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (Int) -> Void

    init(selectedYear: Int, onConfirm: @escaping (Int) -> Void) {
        _draftYear = State(initialValue: selectedYear)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Picker("年份", selection: $draftYear) {
                ForEach(1970...2100, id: \.self) { year in
                    Text("\(year) 年").tag(year)
                }
            }
            .pickerStyle(.automatic)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("选择年份")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onConfirm(draftYear)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DateReviewNotice: View {
    let sourceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("日期未完整识别，当前值只是待确认候选", systemImage: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)
            if let sourceText, !sourceText.isEmpty {
                Text("图片中的日期文字：\(sourceText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("图片中没有可可靠解析的日期，请手动选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CategoryEditor: View {
    @Binding var category: String
    let availableCategories: [String]
    let label: String

    private let customValue = "__custom_category__"
    private let standardCategories = ["餐饮", "交通", "购物", "居住", "旅行", "医疗", "娱乐", "教育", "退款", "其他"]

    var body: some View {
        Picker(label, selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
            Divider()
            Text("自定义…").tag(customValue)
        }

        if selection.wrappedValue == customValue {
            LabeledContent("自定义分类") {
                IMESafeTextField("输入分类名称", text: $category)
            }
        }
    }

    private var options: [String] {
        var result: [String] = []
        for value in standardCategories + availableCategories where !value.isEmpty && !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private var selection: Binding<String> {
        Binding(
            get: { options.contains(category) ? category : customValue },
            set: { newValue in
                if newValue == customValue {
                    if options.contains(category) { category = "" }
                } else {
                    category = newValue
                }
            }
        )
    }
}
