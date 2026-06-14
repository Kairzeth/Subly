import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    var repository: SubscriptionRepository
    var categories: CategoryRepository
    var templates: ServiceTemplateRepository
    var exchangeRates: ExchangeRateRepository
    var settings: AppSettingsRepository
    var commandService: SubscriptionCommandService
    var events: AppEventCenter?
    var onQuickAction: (HomeQuickAction) -> Void = { _ in }
    @State private var isShowingAdd = false

    var body: some View {
        List {
            Section {
                SummaryPanelView(state: viewModel.state)
            }

            Section("订阅") {
                Picker("订阅范围", selection: Binding(
                    get: { viewModel.state.subscriptionScope },
                    set: { viewModel.load(subscriptionScope: $0) }
                )) {
                    ForEach(HomeSubscriptionScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, SublySpacing.xs)

                if viewModel.state.subscriptionRows.isEmpty {
                    if viewModel.state.hasAnySubscriptions {
                        VStack(alignment: .leading, spacing: SublySpacing.sm) {
                            EmptyStateView(title: viewModel.state.subscriptionScope == .active ? "暂无活跃订阅" : "暂无历史订阅", systemImage: "clock.arrow.circlepath")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: SublySpacing.sm) {
                            EmptyStateView(title: "还没有订阅记录", systemImage: "plus.circle")
                            Button {
                                isShowingAdd = true
                            } label: {
                                Label("新增订阅", systemImage: "plus.circle")
                            }
                        }
                    }
                } else {
                    ForEach(viewModel.state.subscriptionRows) { row in
                        NavigationLink {
                            detailView(for: row.id)
                        } label: {
                            SubscriptionRowView(row: row, showsStatus: viewModel.state.subscriptionScope == .history)
                        }
                    }
                }
            }

            Section("即将到期") {
                if viewModel.state.dueSoonRows.isEmpty {
                    EmptyStateView(title: "近 30 天暂无到期项目", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.state.dueSoonRows.prefix(8)) { row in
                        DueSoonRowView(row: row)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(SublyColor.danger)
                }
            }
        }
        .navigationTitle("Subly")
        .toolbar {
            Button {
                isShowingAdd = true
            } label: {
                Label("新增订阅", systemImage: "plus")
            }
        }
        .sheet(isPresented: $isShowingAdd) {
            NavigationStack {
                SubscriptionFormView(
                    viewModel: SubscriptionFormViewModel(
                        commandService: commandService,
                        categoryRepository: categories,
                        templateRepository: templates
                    )
                ) {
                    isShowingAdd = false
                    viewModel.load()
                }
            }
        }
        .onAppear {
            viewModel.load()
        }
        .task {
            viewModel.load()
        }
        .onReceive(events?.publisher ?? NotificationCenter.default.publisher(for: Notification.Name("SublyUnusedHomeEvent"))) { _ in
            viewModel.load()
        }
    }

    private func detailView(for id: UUID) -> some View {
        SubscriptionDetailView(
            viewModel: SubscriptionDetailViewModel(
                id: id,
                queryService: SubscriptionQueryService(repository: repository),
                commandService: commandService
            ),
            aggregationQuery: ServiceAggregationQueryService(
                subscriptions: repository,
                exchangeRates: exchangeRates,
                settings: settings
            ),
            aggregationCommand: ServiceAggregationCommandService(subscriptions: repository),
            categoryRepository: categories,
            onChanged: {
                viewModel.load()
            }
        )
    }
}

private struct SummaryPanelView: View {
    var state: HomeDashboardViewState
    @State private var selectedCard: HomeSummaryCardState?

    var body: some View {
        VStack(alignment: .leading, spacing: SublySpacing.md) {
            HStack {
                Text("总览")
                    .font(.headline)
                Spacer()
                Text("摊销视图")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SublyColor.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(SublyColor.accent.opacity(0.10), in: Capsule())
            }

            HStack(alignment: .top, spacing: SublySpacing.md) {
                ForEach(Array(state.summaryCards.filter { $0.money != nil }.enumerated()), id: \.element.id) { index, card in
                    Button {
                        guard !card.detailRows.isEmpty else { return }
                        selectedCard = card
                    } label: {
                        SummaryMetricView(card: card, tint: SublyColor.chartColor(at: index))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(card.detailRows.isEmpty ? "" : "点击查看摊销明细")
                }
            }

            Divider()

            HStack {
                Label("活跃订阅", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(state.activeCount)")
                    .font(.title3.weight(.semibold))
            }

            if state.isStatisticsIncomplete {
                Label(state.incompleteReason ?? "统计需要补充信息", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(SublyColor.warning)
            }
        }
        .padding(.vertical, SublySpacing.sm)
        .popover(item: $selectedCard) { card in
            AmortizedDetailPopover(card: card)
                .presentationCompactAdaptation(.popover)
        }
    }
}

struct SummaryMetricView: View {
    var card: HomeSummaryCardState
    var tint: Color

    init(card: HomeSummaryCardState) {
        self.card = card
        self.tint = SublyColor.accent
    }

    init(card: HomeSummaryCardState, tint: Color) {
        self.card = card
        self.tint = tint
    }

    init(title: String, money: Money?) {
        self.card = .money(title, title: title, money: money)
        self.tint = SublyColor.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SublySpacing.xs) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint.gradient)
                    .frame(width: 8, height: 8)
                Text(card.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !card.detailRows.isEmpty {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
            if let count = card.count {
                Text("\(count)")
                    .font(.title3.weight(.semibold))
            } else {
                CurrencyAmountText(money: card.money)
            }
        }
        .padding(SublySpacing.sm)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.16), tint.opacity(0.05), SublyColor.surface.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct AmortizedDetailPopover: View {
    var card: HomeSummaryCardState

    var body: some View {
        VStack(alignment: .leading, spacing: SublySpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.headline)
                    Text("每个订阅的摊销金额")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CurrencyAmountText(money: card.money, font: .system(.headline, design: .rounded, weight: .bold))
            }

            if card.detailRows.isEmpty {
                EmptyStateView(title: "暂无摊销明细", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: SublySpacing.sm) {
                        ForEach(Array(card.detailRows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: SublySpacing.sm) {
                                Image(systemName: row.iconName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(SublyColor.chartColor(at: index).gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(row.categoryName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.money.formatted)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .padding(SublySpacing.sm)
                            .background(SublyColor.chartColor(at: index).opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(SublySpacing.md)
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: 460)
    }
}

struct SubscriptionRowView: View {
    var row: SubscriptionRowState
    var showsStatus: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: SublySpacing.md) {
            Image(systemName: row.iconName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SublyColor.accent)
                .frame(width: 32, height: 32)
                .background(SublyColor.surface, in: RoundedRectangle(cornerRadius: SublyCornerRadius.card))

            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if showsStatus {
                        StatusTagView(status: row.status)
                    }
                    Text(row.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(row.billingCycleName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                CurrencyAmountText(money: row.money, font: .system(.subheadline, design: .rounded, weight: .semibold))
                if let date = row.displayDate {
                    Text("\(row.displayDateLabel ?? "日期") \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct DueSoonRowView: View {
    var row: DueSoonRowState

    var body: some View {
        HStack(spacing: SublySpacing.md) {
            VStack(spacing: 2) {
                Text(row.dueDate.formatted(.dateTime.day()))
                    .font(.title3.weight(.semibold))
                Text(row.dueDate.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 48)
            .background(SublyColor.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Label(row.name, systemImage: row.iconName)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Spacer()
            CurrencyAmountText(money: row.money, font: .system(.subheadline, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, SublySpacing.xs)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
