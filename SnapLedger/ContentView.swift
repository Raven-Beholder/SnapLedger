import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            if model.ledger == nil {
                LedgerSelectionView(model: model)
            } else {
                MainLedgerView(model: model)
            }
        }
        .task { await model.restoreLedger() }
        .alert("提示", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct LedgerSelectionView: View {
    let model: AppModel
    @State private var isOpening = false
    @State private var isCreating = false
    @State private var newDocument = LedgerDocument(ledger: Ledger())

    var body: some View {
        ContentUnavailableView {
            Label("截图记账", systemImage: "doc.text.viewfinder")
        } description: {
            Text("创建或打开 iCloud Drive 中的 ledger.json。重新安装后可再次选择同一文件恢复账本。")
        } actions: {
            Button("创建新账本") {
                newDocument = LedgerDocument(ledger: Ledger(defaultCurrency: model.defaultCurrency))
                isCreating = true
            }
            .buttonStyle(.borderedProminent)
            Button("打开已有账本") { isOpening = true }
                .buttonStyle(.bordered)
        }
        .fileImporter(isPresented: $isOpening, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task { await model.openLedger(at: url) }
            } else if case .failure(let error) = result {
                model.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isCreating,
            document: newDocument,
            contentType: .json,
            defaultFilename: "ledger"
        ) { result in
            switch result {
            case .success(let url):
                Task { await model.openLedger(at: url) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
    }
}

struct MainLedgerView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        TabView {
            NavigationStack { TransactionListView(model: model) }
                .tabItem { Label("流水", systemImage: "list.bullet.rectangle") }
            NavigationStack { ImportView(model: model) }
                .tabItem { Label("导入", systemImage: "doc.viewfinder") }
            NavigationStack { StatisticsView(model: model) }
                .tabItem { Label("统计", systemImage: "chart.bar") }
            NavigationStack { SettingsView(model: model) }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .sheet(item: $model.selectedTransaction) { transaction in
            ConfirmationView(
                transaction: transaction,
                lowConfidenceFields: [],
                onSave: { updated in
                    Task {
                        await model.confirm(updated)
                        model.selectedTransaction = nil
                    }
                },
                onCancel: { model.selectedTransaction = nil }
            )
        }
    }
}

struct TransactionListView: View {
    let model: AppModel
    @State private var isShowingFilters = false

    var body: some View {
        List {
            ForEach(monthGroups) { group in
                Section(group.title) {
                    ForEach(group.transactions) { transaction in
                        TransactionRow(transaction: transaction)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedTransaction = transaction }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    Task { await model.delete(transaction) }
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("流水")
        .searchable(text: Bindable(model).searchText, prompt: "商户或分类")
        .toolbar {
            ToolbarItem {
                Button("筛选", systemImage: "line.3.horizontal.decrease.circle") {
                    isShowingFilters = true
                }
            }
        }
        .sheet(isPresented: $isShowingFilters) { FilterView(model: model) }
        .overlay {
            if model.visibleTransactions.isEmpty {
                ContentUnavailableView("暂无流水", systemImage: "tray", description: Text("导入支付截图后，确认交易即可写入账本。"))
            }
        }
    }

    private var monthGroups: [TransactionMonthGroup] {
        Dictionary(grouping: model.visibleTransactions) {
            Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        }
        .map { TransactionMonthGroup(month: $0.key, transactions: $0.value) }
        .sorted { $0.month > $1.month }
    }
}

struct TransactionMonthGroup: Identifiable {
    let month: Date
    let transactions: [LedgerTransaction]
    var id: Date { month }
    var title: String { month.formatted(.dateTime.year().month(.wide)) }
}

struct TransactionRow: View {
    let transaction: LedgerTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                Text("\(transaction.category) · \(transaction.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(transaction.currency.rawValue) \(DecimalCoding.string(from: transaction.amount))")
                    .monospacedDigit()
                Text(transaction.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FilterView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("币种", selection: Bindable(model).currencyFilter) {
                    Text("全部").tag(Currency?.none)
                    ForEach(Currency.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("类型", selection: Bindable(model).typeFilter) {
                    Text("全部").tag(TransactionType?.none)
                    ForEach(TransactionType.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("分类", selection: Bindable(model).categoryFilter) {
                    Text("全部").tag(String?.none)
                    ForEach(model.categories, id: \.self) { Text($0).tag(Optional($0)) }
                }
                Button("清除筛选") {
                    model.currencyFilter = nil
                    model.typeFilter = nil
                    model.categoryFilter = nil
                }
            }
            .navigationTitle("筛选")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct ImportView: View {
    let model: AppModel
    #if os(iOS)
    @State private var photoItems: [PhotosPickerItem] = []
    #else
    @State private var isChoosingImages = false
    #endif

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("图片只用于本次设备端识别；完成或取消后立即释放，不会保存截图或 OCR 文本。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            #if os(iOS)
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 20,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Label("选择支付截图", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
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
            Button("选择图片") { isChoosingImages = true }
                .buttonStyle(.borderedProminent)
            Text("也可以把图片拖到此处")
                .padding(30)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                .dropDestination(for: URL.self) { urls, _ in
                    let data = urls.filter { $0.isFileURL }.compactMap { try? Data(contentsOf: $0) }
                    if !data.isEmpty { model.importImages(data) }
                    return !data.isEmpty
                }
            #endif

            switch model.importState {
            case .idle:
                EmptyView()
            case .processing(let current, let total):
                ProgressView(value: Double(current), total: Double(max(total, 1))) {
                    Text("正在识别 \(current)/\(total)")
                }
                Button("取消", role: .cancel) { model.cancelImport() }
            case .reviewing:
                ReviewQueueView(model: model)
            }
        }
        .padding()
        .navigationTitle("导入截图")
        #if os(macOS)
        .fileImporter(
            isPresented: $isChoosingImages,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let images = urls.compactMap { try? Data(contentsOf: $0) }
                if !images.isEmpty { model.importImages(images) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        #endif
    }
}

struct ReviewQueueView: View {
    let model: AppModel

    var body: some View {
        VStack {
            Text("待确认：\(model.pendingTransactions.count)")
                .font(.headline)
            if let candidate = model.pendingTransactions.first {
                Text("解析方式：\(candidate.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("确认第一笔交易") {
                    model.selectedTransaction = candidate.transaction
                }
                .buttonStyle(.borderedProminent)
            }
            Button("取消全部", role: .cancel) { model.cancelImport() }
        }
    }
}

struct ConfirmationView: View {
    @State private var draft: LedgerTransaction
    @State private var amountText: String
    let lowConfidenceFields: Set<String>
    let onSave: (LedgerTransaction) -> Void
    let onCancel: () -> Void
    @State private var validationMessage: String?

    init(
        transaction: LedgerTransaction,
        lowConfidenceFields: Set<String>,
        onSave: @escaping (LedgerTransaction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: transaction)
        _amountText = State(initialValue: DecimalCoding.string(from: transaction.amount))
        self.lowConfidenceFields = lowConfidenceFields
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $draft.type) {
                    ForEach(TransactionType.allCases) { Text($0.displayName).tag($0) }
                }
                TextField(fieldLabel("金额", key: "amount"), text: $amountText)
                Picker(fieldLabel("币种", key: "currency"), selection: $draft.currency) {
                    ForEach(Currency.allCases) { Text("\($0.rawValue) · \($0.displayName)").tag($0) }
                }
                TextField(fieldLabel("商户", key: "merchant"), text: $draft.merchant)
                TextField("分类", text: $draft.category)
                DatePicker(fieldLabel("日期", key: "date"), selection: $draft.date)
                TextField("支付方式", text: optionalBinding(\.paymentMethod))
                TextField("备注", text: optionalBinding(\.note), axis: .vertical)
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("确认交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("写入账本") {
                        guard let amount = DecimalCoding.decimal(from: amountText), amount > 0 else {
                            validationMessage = UserFacingError.invalidAmount.errorDescription
                            return
                        }
                        guard !draft.merchant.trimmingCharacters(in: .whitespaces).isEmpty else {
                            validationMessage = "请填写商户。"
                            return
                        }
                        draft.amount = amount
                        onSave(draft)
                    }
                }
            }
        }
    }

    private func fieldLabel(_ title: String, key: String) -> String {
        lowConfidenceFields.contains(key) ? "\(title)（请确认）" : title
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<LedgerTransaction, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

struct StatisticsView: View {
    let model: AppModel

    var body: some View {
        List {
            ForEach(Currency.allCases) { currency in
                Section("\(currency.rawValue) · \(currency.displayName)") {
                    ForEach(categoryTotals(for: currency), id: \.category) { item in
                        HStack {
                            Text(item.category)
                            Spacer()
                            Text(DecimalCoding.string(from: item.total)).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("本月统计")
    }

    private func categoryTotals(for currency: Currency) -> [(category: String, total: Decimal)] {
        let calendar = Calendar.current
        let items = (model.ledger?.transactions ?? []).filter {
            $0.currency == currency && calendar.isDate($0.date, equalTo: .now, toGranularity: .month)
        }
        return Dictionary(grouping: items, by: \.category)
            .map { ($0.key, $0.value.reduce(Decimal.zero) { $0 + $1.amount }) }
            .sorted { $0.0 < $1.0 }
    }
}

struct SettingsView: View {
    let model: AppModel
    @State private var isOpening = false
    @State private var isExporting = false
    @State private var csvDocument = CSVDocument(data: Data())

    var body: some View {
        Form {
            Picker("默认币种", selection: Bindable(model).defaultCurrency) {
                ForEach(Currency.allCases) { Text("\($0.rawValue) · \($0.displayName)").tag($0) }
            }
            .onChange(of: model.defaultCurrency) { _, _ in Task { await model.saveSettings() } }

            LabeledContent("当前账本", value: model.ledgerURL?.path(percentEncoded: false) ?? "未选择")
            LabeledContent("Foundation Models", value: model.foundationModelStatus)
            Button("重新选择账本") { isOpening = true }
            Button("导出 CSV") {
                csvDocument = CSVDocument(data: CSVExporter().data(for: model.ledger ?? Ledger()))
                isExporting = true
            }
            Section("隐私") {
                Text("OCR 与交易整理在设备端完成。App 不上传、不保存截图、凭证、附件或 OCR 临时文本。")
            }
        }
        .navigationTitle("设置")
        .fileImporter(isPresented: $isOpening, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { Task { await model.openLedger(at: url) } }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "ledger"
        ) { result in
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
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

#Preview {
    ContentView()
}
