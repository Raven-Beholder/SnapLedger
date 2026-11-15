import SwiftUI
import UniformTypeIdentifiers

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

#if DEBUG
#Preview("完整账本") {
    @Previewable @State var model = PreviewData.appModel()
    MainLedgerView(model: model)
}
#endif

struct LedgerSelectionView: View {
    let model: AppModel
    @State private var isOpening = false
    @State private var isCreating = false
    #if os(iOS)
    @State private var creationSourceURL: URL?
    #else
    @State private var newDocument = LedgerDocument(ledger: Ledger())
    #endif

    var body: some View {
        ContentUnavailableView {
            Label("截图记账", systemImage: "doc.text.viewfinder")
        } description: {
            Text("创建或打开 iCloud Drive 中的 ledger.json。重新安装后可再次选择同一文件恢复账本。")
        } actions: {
            Button("创建新账本") {
                beginCreatingLedger()
            }
            .buttonStyle(.borderedProminent)
            Button("打开已有账本") { isOpening = true }
                .buttonStyle(.bordered)
        }
        .fileImporter(isPresented: $isOpening, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task { await model.openLedger(at: url) }
            } else if case .failure(let error) = result {
                model.present(error)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isCreating) {
            if let creationSourceURL {
                LedgerMovePicker(
                    sourceURL: creationSourceURL,
                    onPick: { destinationURL in
                        await model.openLedger(at: destinationURL)
                        isCreating = false
                        self.creationSourceURL = nil
                    },
                    onCancel: {
                        isCreating = false
                        self.creationSourceURL = nil
                    }
                )
                .ignoresSafeArea()
            }
        }
        #else
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
                model.present(error)
            }
        }
        #endif
    }

    private func beginCreatingLedger() {
        let ledger = Ledger(defaultCurrency: model.defaultCurrency)
        #if os(iOS)
        do {
            creationSourceURL = try TemporaryLedgerFile.create(ledger: ledger)
            isCreating = true
        } catch {
            model.present(error)
        }
        #else
        newDocument = LedgerDocument(ledger: ledger)
        isCreating = true
        #endif
    }
}

struct MainLedgerView: View {
    let model: AppModel
    #if os(macOS)
    @State private var selectedSection: LedgerSection? = .transactions
    #endif

    var body: some View {
        @Bindable var model = model
        #if os(macOS)
        NavigationSplitView {
            LedgerSidebar(selection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            NavigationStack {
                switch selectedSection ?? .transactions {
                case .transactions:
                    TransactionListView(model: model)
                case .importImages:
                    ImportView(model: model)
                case .statistics:
                    StatisticsView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $model.selectedTransaction) { transaction in
            transactionConfirmation(for: transaction)
        }
        #else
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
            transactionConfirmation(for: transaction)
        }
        #endif
    }

    private func transactionConfirmation(for transaction: LedgerTransaction) -> some View {
        ConfirmationView(
            transaction: transaction,
            lowConfidenceFields: model.selectedLowConfidenceFields,
            parserSource: model.selectedParserSource,
            dateSourceText: model.selectedDateSourceText,
            sourceImageData: model.selectedSourceImageData,
            generationMetrics: model.selectedGenerationMetrics,
            structuredOutput: model.selectedStructuredOutput,
            availableCategories: model.categories,
            availablePaymentMethods: model.paymentMethods,
            canDiscard: model.pendingTransactions.contains { $0.transaction.id == transaction.id },
            onSave: { updated in
                Task { await model.confirm(updated) }
            },
            onDiscard: {
                model.discardPending(transaction)
            },
            onCancel: {
                model.closeReview()
            }
        )
    }
}

#if os(macOS)
private enum LedgerSection: String, CaseIterable, Identifiable {
    case transactions
    case importImages
    case statistics
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .transactions: "流水"
        case .importImages: "导入"
        case .statistics: "统计"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .transactions: "list.bullet.rectangle"
        case .importImages: "doc.viewfinder"
        case .statistics: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

private struct LedgerSidebar: View {
    @Binding var selection: LedgerSection?

    var body: some View {
        List(LedgerSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.symbolName)
                .tag(section)
                .padding(.vertical, 3)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.gradient)
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("截图账本")
                        .font(.headline)
                    Text("SnapLedger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("截图账本")
    }
}
#endif
