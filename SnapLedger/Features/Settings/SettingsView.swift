import SwiftUI
import UniformTypeIdentifiers
struct SettingsView: View {
    let model: AppModel
    @State private var isOpening = false
    @State private var isExporting = false
    @State private var csvDocument = CSVDocument(data: Data())
    @State private var recognitionGuidance = ""
    @FocusState private var isRecognitionGuidanceFocused: Bool

    var body: some View {
        Group {
        #if os(macOS)
        MacSettingsContent(
            model: model,
            recognitionGuidance: $recognitionGuidance,
            onSaveGuidance: saveRecognitionGuidance,
            onChooseLedger: { isOpening = true },
            onExport: prepareExport
        )
        #else
        Form {
            Section("通用") {
                Picker("默认币种", selection: Bindable(model).defaultCurrency) {
                    ForEach(Currency.allCases) { Text("\($0.rawValue) · \($0.displayName)").tag($0) }
                }
                .onChange(of: model.defaultCurrency) { _, _ in Task { await model.saveSettings() } }

                LabeledContent("当前账本") {
                    Text(model.ledgerURL?.path(percentEncoded: false) ?? "未选择")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                LabeledContent("设备端模型", value: model.foundationModelStatus)
                NavigationLink("管理分类") {
                    CategoryManagementView(model: model)
                }
                NavigationLink("管理支付方式") {
                    PaymentMethodManagementView(model: model)
                }
            }

            Section {
                TextEditor(text: $recognitionGuidance)
                    .frame(minHeight: 110)
                    .focused($isRecognitionGuidanceFocused)
                Button("保存识别偏好") {
                    isRecognitionGuidanceFocused = false
                    Task { await model.updateRecognitionGuidance(recognitionGuidance) }
                }
            } header: {
                Text("识别偏好")
            } footer: {
                Text("例如：“Keeta 是外卖平台，归为餐饮；MUJI 通常归为购物”。偏好仅作为识别上下文，金额仍必须来自截图证据。")
            }

            Section("数据") {
                Button("重新选择账本", systemImage: "folder") { isOpening = true }
                Button("导出 CSV", systemImage: "square.and.arrow.up") {
                    csvDocument = CSVDocument(data: CSVExporter().data(for: model.ledger ?? Ledger()))
                    isExporting = true
                }
            }

            Section("快捷指令云端识别") {
                CloudShortcutSetupHelp()
            }

            Section("隐私") {
                Label {
                    Text("OCR 与交易整理在设备端完成。App 不上传、不保存截图、凭证、附件或 OCR 临时文本。")
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        #endif
        }
        .navigationTitle("设置")
        .task { recognitionGuidance = model.ledger?.recognitionGuidance ?? "" }
        .fileImporter(isPresented: $isOpening, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { Task { await model.openLedger(at: url) } }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "ledger"
        ) { result in
            if case .failure(let error) = result { model.present(error) }
        }
    }

    private func saveRecognitionGuidance() {
        isRecognitionGuidanceFocused = false
        Task { await model.updateRecognitionGuidance(recognitionGuidance) }
    }

    private func prepareExport() {
        csvDocument = CSVDocument(data: CSVExporter().data(for: model.ledger ?? Ledger()))
        isExporting = true
    }
}

#if os(macOS)
private struct MacSettingsContent: View {
    let model: AppModel
    @Binding var recognitionGuidance: String
    let onSaveGuidance: () -> Void
    let onChooseLedger: () -> Void
    let onExport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MacSettingsSection(title: "通用", systemImage: "gearshape") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                        GridRow {
                            Text("默认币种")
                                .foregroundStyle(.secondary)
                            Picker("默认币种", selection: Bindable(model).defaultCurrency) {
                                ForEach(Currency.allCases) {
                                    Text("\($0.rawValue) · \($0.displayName)").tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220, alignment: .leading)
                            .onChange(of: model.defaultCurrency) { _, _ in
                                Task { await model.saveSettings() }
                            }
                        }
                        GridRow {
                            Text("当前账本")
                                .foregroundStyle(.secondary)
                            Text(model.ledgerURL?.path(percentEncoded: false) ?? "未选择")
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("设备端模型")
                                .foregroundStyle(.secondary)
                            Text(model.foundationModelStatus)
                        }
                    }
                    Divider()
                    NavigationLink {
                        CategoryManagementView(model: model)
                    } label: {
                        Label("管理分类", systemImage: "tag")
                    }
                    NavigationLink {
                        PaymentMethodManagementView(model: model)
                    } label: {
                        Label("管理支付方式", systemImage: "creditcard")
                    }
                }

                MacSettingsSection(title: "识别偏好", systemImage: "text.badge.checkmark") {
                    TextEditor(text: $recognitionGuidance)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 120)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                    Text("例如：“Keeta 是外卖平台，归为餐饮；MUJI 通常归为购物”。偏好只作为识别上下文。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("保存识别偏好", systemImage: "checkmark") {
                        onSaveGuidance()
                    }
                    .buttonStyle(.borderedProminent)
                }

                MacSettingsSection(title: "数据", systemImage: "externaldrive") {
                    HStack {
                        Button("重新选择账本", systemImage: "folder", action: onChooseLedger)
                        Button("导出 CSV", systemImage: "square.and.arrow.up", action: onExport)
                    }
                }

                MacSettingsSection(title: "快捷指令云端识别", systemImage: "wand.and.stars") {
                    CloudShortcutSetupHelp()
                }

                MacSettingsSection(title: "隐私", systemImage: "hand.raised") {
                    Label {
                        Text("OCR 与交易整理在设备端完成。App 不上传、不保存截图、凭证、附件或 OCR 临时文本。")
                    } icon: {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MacSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }
}
#endif

private struct CloudShortcutSetupHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在“快捷指令”App 中新建快捷指令，并依次添加：")
            Text("1. 选择照片或接收截图")
            Text("2. 获取 SnapLedger 云端解析指令")
            Text("3. 使用模型，并选择 Cloud 或 Cloud Pro")
            Text("4. 导入云端模型结果到 SnapLedger")
            Text("截图由快捷指令选择的模型处理；SnapLedger 只接收并校验模型返回的 JSON。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CategoryManagementView: View {
    let model: AppModel
    @State private var editingCategory: LedgerCategory?
    @State private var isAdding = false

    var body: some View {
        List {
            ForEach(CategoryKind.allCases) { kind in
                Section(kind.displayName) {
                    ForEach((model.ledger?.categories ?? []).filter { $0.kind == kind }) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            HStack {
                                Label(category.name, systemImage: category.symbolName)
                                Spacer()
                                if category.isArchived {
                                    Text("已停用").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                Task { await model.deleteCategory(category) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新增", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditView(category: category) { updated in
                Task { await model.updateCategory(updated, previousName: category.name) }
            }
        }
        .sheet(isPresented: $isAdding) {
            CategoryEditView(category: .init(name: "", symbolName: "tag.fill", kind: .expense)) { category in
                Task { await model.addCategory(name: category.name, kind: category.kind, symbolName: category.symbolName) }
            }
        }
    }
}

private struct CategoryEditView: View {
    @State private var category: LedgerCategory
    @State private var nameText: String
    let onSave: (LedgerCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    private let symbols = ["fork.knife", "cup.and.saucer.fill", "car.fill", "bag.fill", "house.fill", "airplane", "cross.case.fill", "gamecontroller.fill", "book.fill", "gift.fill", "banknote.fill", "tag.fill"]

    init(category: LedgerCategory, onSave: @escaping (LedgerCategory) -> Void) {
        _category = State(initialValue: category)
        _nameText = State(initialValue: category.name)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CategoryIcon(
                            category: previewCategory,
                            tint: CategoryTints(names: [nameText]).tint(for: nameText),
                            size: 48
                        )
                        IMESafeTextField("分类名称", text: $nameText, alignment: .leading)
                    }
                    Picker("类型", selection: $category.kind) {
                        ForEach(CategoryKind.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section("图标") {
                    SymbolPickerGrid(symbols: symbols, selection: $category.symbolName)
                }

                Section {
                    Toggle("停用此分类", isOn: $category.isArchived)
                }
            }
            .navigationTitle(nameText.isEmpty ? "新增分类" : "编辑分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = category
                        updated.name = nameText
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var previewCategory: LedgerCategory {
        var preview = category
        preview.name = nameText
        return preview
    }
}

private struct SymbolPickerGrid: View {
    let symbols: [String]
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(selection == symbol ? Color.accentColor : .secondary)
                        .background(
                            selection == symbol ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selection == symbol ? Color.accentColor : .clear, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct PaymentMethodManagementView: View {
    let model: AppModel
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                ForEach(model.ledger?.paymentMethods ?? [], id: \.self) { method in
                    Label(method, systemImage: "creditcard")
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                Task { await model.deletePaymentMethod(method) }
                            }
                        }
                }
            } footer: {
                Text("模型会优先采用与截图证据相符的已维护支付方式。历史记录中的支付方式仍可在交易确认时选择。")
            }
        }
        .navigationTitle("支付方式")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新增", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            PaymentMethodAddView { name in
                Task { await model.addPaymentMethod(name) }
            }
        }
    }
}

private struct PaymentMethodAddView: View {
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                IMESafeTextField("例如：微信支付、Visa •••• 1234", text: $name, alignment: .leading)
            }
            .navigationTitle("新增支付方式")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if DEBUG
#Preview("设置") {
    @Previewable @State var model = PreviewData.appModel()
    NavigationStack {
        SettingsView(model: model)
    }
}
#endif
