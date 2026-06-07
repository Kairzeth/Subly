import Charts
import SwiftUI

struct StatisticsView: View {
    @StateObject var viewModel: StatisticsViewModel
    var events: AppEventCenter?
    @State private var categoryScope: StatisticsPeriodScope = .month
    @State private var serviceScope: StatisticsPeriodScope = .month
    @State private var selectedMonthlyPoint: PeriodCost?
    @State private var selectedYearlyPoint: PeriodCost?

    var body: some View {
        List {
            Section {
                PeriodScopePicker(selection: $categoryScope)
                CategoryBarChart(items: categoryItems)
            } header: {
                Text("分类占比")
            }

            Section {
                PeriodScopePicker(selection: $serviceScope)
                ServiceRankingChart(items: serviceItems)
            } header: {
                Text("服务排名")
            }

            Section("月度趋势") {
                TrendLineChart(items: viewModel.state.monthlyTrend, selectedItem: $selectedMonthlyPoint)
            }

            Section("年度趋势") {
                TrendLineChart(items: viewModel.state.yearlyTrend, selectedItem: $selectedYearlyPoint)
            }

            if viewModel.state.isIncomplete {
                Section {
                    Label(viewModel.state.incompleteReason ?? "统计不完整", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(SublyColor.warning)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(SublyColor.danger)
                }
            }
        }
        .navigationTitle("统计")
        .task {
            viewModel.load()
        }
        .onReceive(events?.publisher ?? NotificationCenter.default.publisher(for: Notification.Name("SublyUnusedStatisticsEvent"))) { _ in
            viewModel.load()
        }
    }

    private var categoryItems: [CategoryCost] {
        categoryScope == .month ? viewModel.state.monthCategories : viewModel.state.yearCategories
    }

    private var serviceItems: [ServiceCost] {
        serviceScope == .month ? viewModel.state.monthServices : viewModel.state.yearServices
    }
}

private struct PeriodScopePicker: View {
    @Binding var selection: StatisticsPeriodScope

    var body: some View {
        Picker("统计范围", selection: $selection) {
            ForEach(StatisticsPeriodScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct CategoryBarChart: View {
    var items: [CategoryCost]

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: "暂无分类统计", systemImage: "chart.pie")
        } else {
            Chart(items.prefix(8).map { $0 }) { item in
                BarMark(
                    x: .value("金额", item.money.chartValue),
                    y: .value("分类", item.name)
                )
                .foregroundStyle(SublyColor.accent.gradient)
                .annotation(position: .trailing) {
                    Text(item.money.formatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: chartHeight(count: items.count))
        }
    }
}

private struct ServiceRankingChart: View {
    var items: [ServiceCost]

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: "暂无服务排行", systemImage: "list.number")
        } else {
            Chart(items.prefix(8).map { $0 }) { item in
                BarMark(
                    x: .value("金额", item.money.chartValue),
                    y: .value("服务", item.name)
                )
                .foregroundStyle(.blue.gradient)
                .annotation(position: .trailing) {
                    Text(item.money.formatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: chartHeight(count: items.count))
        }
    }
}

private struct TrendLineChart: View {
    var items: [PeriodCost]
    @Binding var selectedItem: PeriodCost?

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: "暂无趋势数据", systemImage: "chart.xyaxis.line")
        } else {
            Chart {
                ForEach(items) { item in
                    LineMark(
                        x: .value("周期", item.title),
                        y: .value("金额", item.money.chartValue)
                    )
                    .foregroundStyle(SublyColor.accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("周期", item.title),
                        y: .value("金额", item.money.chartValue)
                    )
                    .foregroundStyle(SublyColor.accent)
                }

                if let selectedItem {
                    RuleMark(x: .value("周期", selectedItem.title))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .annotation(position: .top, alignment: .center) {
                            VStack(spacing: 2) {
                                Text(selectedItem.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(selectedItem.money.formatted)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SublyCornerRadius.card))
                        }
                }
            }
            .frame(height: 220)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let origin = geometry[plotFrame].origin
                                    let x = value.location.x - origin.x
                                    if let title: String = proxy.value(atX: x) {
                                        selectedItem = items.first { $0.title == title }
                                    }
                                }
                        )
                }
            }
        }
    }
}

private func chartHeight(count: Int) -> CGFloat {
    CGFloat(max(3, min(8, count))) * 38
}

private extension Money {
    var chartValue: Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }
}
