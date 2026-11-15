import SwiftUI
import Charts

struct StatisticsView: View {
    let model: AppModel

    var body: some View {
        let tints = CategoryTints(names: model.ledger?.knownCategoryNames ?? [])
        #if os(macOS)
        MacStatisticsContent(statistics: visibleStatistics, tints: tints)
            .navigationTitle("本月统计")
        #else
        List {
            ForEach(visibleStatistics) { statistic in
                Section {
                    CategorySpendingChart(
                        currency: statistic.currency,
                        items: statistic.items,
                        tints: tints
                    )
                } header: {
                    CurrencySectionHeader(
                        code: statistic.currency.rawValue,
                        name: statistic.currency.displayName,
                        total: statistic.items.reduce(Decimal.zero) { $0 + $1.total }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("本月统计")
        .overlay {
            if visibleStatistics.isEmpty {
                ContentUnavailableView(
                    "本月暂无支出",
                    systemImage: "chart.pie",
                    description: Text("本月的支出交易会显示在这里。")
                )
            }
        }
        #endif
    }

    private var statistics: [CurrencyStatistic] {
        Currency.allCases.map { CurrencyStatistic(currency: $0, items: categoryTotals(for: $0)) }
    }

    private var visibleStatistics: [CurrencyStatistic] {
        statistics.filter { !$0.items.isEmpty }
    }

    private func categoryTotals(for currency: Currency) -> [CategorySpending] {
        let calendar = Calendar.current
        let items = (model.ledger?.transactions ?? []).filter {
            $0.currency == currency &&
            $0.type == .expense &&
            calendar.isDate($0.date, equalTo: .now, toGranularity: .month)
        }
        return Dictionary(grouping: items, by: \.category)
            .map { category, transactions in
                CategorySpending(
                    category: category,
                    total: transactions.reduce(Decimal.zero) { $0 + $1.amount }
                )
            }
            .sorted { $0.total > $1.total }
    }
}

private struct CurrencyStatistic: Identifiable {
    var id: Currency { currency }
    let currency: Currency
    let items: [CategorySpending]
}

#if os(macOS)
private struct MacStatisticsContent: View {
    let statistics: [CurrencyStatistic]
    let tints: CategoryTints

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18)], spacing: 18) {
                ForEach(statistics) { statistic in
                    MacCurrencyCard(statistic: statistic, tints: tints)
                }
            }
            .padding(24)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MacCurrencyCard: View {
    let statistic: CurrencyStatistic
    let tints: CategoryTints

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(statistic.currency.rawValue)
                        .font(.title2.weight(.semibold))
                    Text(statistic.currency.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(totalText)
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
            }

            if statistic.items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "chart.pie")
                        .foregroundStyle(.secondary)
                    Text("本月暂无支出")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(minHeight: 92)
            } else {
                CategorySpendingChart(
                    currency: statistic.currency,
                    items: statistic.items,
                    tints: tints
                )
            }
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private var totalText: String {
        let total = statistic.items.reduce(Decimal.zero) { $0 + $1.total }
        return "\(statistic.currency.rawValue) \(DecimalCoding.string(from: total))"
    }
}
#endif

#Preview("统计") {
    @Previewable @State var model = PreviewData.appModel()
    NavigationStack {
        StatisticsView(model: model)
    }
}

private struct CategorySpending: Identifiable {
    var id: String { category }
    let category: String
    let total: Decimal
}

private struct CategorySpendingChart: View {
    let currency: Currency
    let items: [CategorySpending]
    let tints: CategoryTints

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "本月暂无支出",
                systemImage: "chart.pie",
                description: Text("该币种本月还没有支出交易。")
            )
        } else {
            VStack(spacing: 20) {
                ZStack {
                    Chart(items) { item in
                        SectorMark(
                            angle: .value("金额", item.total),
                            innerRadius: .ratio(0.66),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(tints.tint(for: item.category))
                    }

                    VStack(spacing: 3) {
                        Text("本月支出")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(currency.rawValue) \(DecimalCoding.string(from: total))")
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
                .frame(height: 220)
                .accessibilityLabel("\(currency.rawValue) 本月分类支出环形图，合计 \(DecimalCoding.string(from: total))")

                VStack(spacing: 12) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tints.tint(for: item.category))
                                .frame(width: 8, height: 8)
                            Text(item.category)
                            Spacer()
                            Text("\(currency.rawValue) \(DecimalCoding.string(from: item.total))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var total: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.total }
    }
}

private struct CurrencySectionHeader: View {
    let code: String
    let name: String
    let total: Decimal

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(code) · \(name)")
            Spacer()
            Text(DecimalCoding.string(from: total))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }
}
