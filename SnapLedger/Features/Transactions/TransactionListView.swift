import SwiftUI

struct TransactionListView: View {
    let model: AppModel
    @State private var isShowingFilters = false

    var body: some View {
        let tints = CategoryTints(names: model.ledger?.knownCategoryNames ?? [])
        List {
            ForEach(monthGroups) { group in
                Section {
                    ForEach(group.transactions) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            category: model.category(named: transaction.category),
                            tint: tints.tint(for: transaction.category)
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedTransaction = transaction }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    Task { await model.delete(transaction) }
                                }
                            }
                    }
                } header: {
                    TransactionMonthHeader(
                        title: group.title,
                        transactionCount: group.transactions.count
                    )
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("流水")
        .searchable(text: Bindable(model).searchText, prompt: "商户或分类")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("手动记账", systemImage: "plus") {
                    model.beginManualTransaction()
                }
                Button("筛选", systemImage: "line.3.horizontal.decrease.circle") {
                    isShowingFilters = true
                }
                .symbolVariant(hasActiveFilters ? .fill : .none)
                .tint(hasActiveFilters ? .accentColor : nil)
            }
        }
        .sheet(isPresented: $isShowingFilters) { FilterView(model: model) }
        .overlay {
            if model.visibleTransactions.isEmpty {
                if hasActiveFilters || !model.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("没有符合条件的流水", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("尝试修改搜索内容或清除筛选条件。")
                    } actions: {
                        Button("清除筛选") { clearFilters() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView(
                        "暂无流水",
                        systemImage: "tray",
                        description: Text("可以手动记账，或导入支付截图后确认交易。")
                    )
                }
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

    private var hasActiveFilters: Bool {
        model.currencyFilter != nil || model.typeFilter != nil || model.categoryFilter != nil
    }

    private func clearFilters() {
        model.searchText = ""
        model.currencyFilter = nil
        model.typeFilter = nil
        model.categoryFilter = nil
    }
}

#if DEBUG
#Preview("流水列表") {
    @Previewable @State var model = PreviewData.appModel()
    NavigationStack {
        TransactionListView(model: model)
    }
}
#endif

struct TransactionMonthGroup: Identifiable {
    let month: Date
    let transactions: [LedgerTransaction]
    var id: Date { month }
    var title: String { month.formatted(.dateTime.year().month(.wide)) }
}

struct TransactionRow: View {
    let transaction: LedgerTransaction
    let category: LedgerCategory?
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(transaction.category) · \(transaction.date.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                Text(transaction.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var amountColor: Color {
        transaction.type == .income || transaction.type == .refund ? .green : .primary
    }

    private var amountText: String {
        let prefix = transaction.type == .income || transaction.type == .refund ? "+" : transaction.type == .expense ? "−" : ""
        return "\(prefix)\(transaction.currency.rawValue) \(DecimalCoding.string(from: transaction.amount))"
    }
}

private struct TransactionMonthHeader: View {
    let title: String
    let transactionCount: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(transactionCount) 笔")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(nil)
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
