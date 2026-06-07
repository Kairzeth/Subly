import SwiftUI

struct StatisticsView: View {
    @StateObject var viewModel: StatisticsViewModel
    var events: AppEventCenter?

    var body: some View {
        List {
            Section {
                SpendingBreakdownCard(
                    title: "分类",
                    subtitle: "历史累计支出",
                    systemImage: "square.grid.2x2",
                    items: viewModel.state.categories.map {
                        SpendingBreakdownItem(id: $0.id.uuidString, name: $0.name, money: $0.money)
                    }
                )
            } header: {
                Text("分类")
            }

            Section {
                SpendingBreakdownCard(
                    title: "服务",
                    subtitle: "历史累计支出",
                    systemImage: "rectangle.stack",
                    items: viewModel.state.services.map {
                        SpendingBreakdownItem(id: $0.id, name: $0.name, money: $0.money)
                    }
                )
            } header: {
                Text("服务")
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
}

private struct SpendingBreakdownItem: Identifiable, Equatable {
    var id: String
    var name: String
    var money: Money

    var value: Decimal {
        money.amount
    }
}

private struct SpendingBreakdownCard: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var items: [SpendingBreakdownItem]

    private var visibleItems: [SpendingBreakdownItem] {
        Array(items.prefix(8))
    }

    private var maxAmount: Decimal {
        visibleItems.map(\.value).max() ?? 0
    }

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: "暂无\(title)统计", systemImage: systemImage)
        } else {
            VStack(alignment: .leading, spacing: SublySpacing.md) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    SpendingBreakdownRow(
                        rank: index + 1,
                        item: item,
                        fraction: fraction(for: item),
                        tint: SublyColor.chartColor(at: index)
                    )
                }
            }
            .padding(.vertical, SublySpacing.xs)
        }
    }

    private func fraction(for item: SpendingBreakdownItem) -> Double {
        guard maxAmount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: item.value / maxAmount).doubleValue)
    }
}

private struct SpendingBreakdownRow: View {
    var rank: Int
    var item: SpendingBreakdownItem
    var fraction: Double
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SublySpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(rank)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint.gradient, in: Circle())
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(item.money.formatted)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.62)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geometry.size.width * fraction))
                }
            }
            .frame(height: 9)
        }
        .padding(SublySpacing.sm)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }
}
