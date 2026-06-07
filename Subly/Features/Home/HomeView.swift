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

    var body: some View {
        VStack(alignment: .leading, spacing: SublySpacing.md) {
            Text("总计")
                .font(.headline)

            HStack(alignment: .top, spacing: SublySpacing.md) {
                ForEach(state.summaryCards.filter { $0.money != nil }) { card in
                    SummaryMetricView(card: card)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

struct SummaryMetricView: View {
    var card: HomeSummaryCardState

    init(card: HomeSummaryCardState) {
        self.card = card
    }

    init(title: String, money: Money?) {
        self.card = .money(title, title: title, money: money)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let count = card.count {
                Text("\(count)")
                    .font(.title3.weight(.semibold))
            } else {
                CurrencyAmountText(money: card.money)
            }
        }
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
                    .lineLimit(1)
                HStack {
                    if showsStatus {
                        StatusTagView(status: row.status)
                    }
                    Text(row.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.billingCycleName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                CurrencyAmountText(money: row.money, font: .system(.subheadline, design: .rounded, weight: .semibold))
                if let date = row.nextBillingDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
            .background(SublyColor.surface, in: RoundedRectangle(cornerRadius: SublyCornerRadius.card))

            VStack(alignment: .leading, spacing: 4) {
                Label(row.name, systemImage: row.iconName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(row.status == .trial ? "试用到期" : "订阅扣费")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CurrencyAmountText(money: row.money, font: .system(.subheadline, design: .rounded, weight: .semibold))
        }
        .padding(.vertical, 2)
    }
}
