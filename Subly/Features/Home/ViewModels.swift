import Foundation

struct SubscriptionRowState: Identifiable, Equatable {
    var id: UUID
    var name: String
    var money: Money
    var status: SubscriptionStatus
    var categoryName: String
    var billingCycleName: String
    var displayDate: Date?
    var displayDateLabel: String?
    var iconName: String
}

struct ReminderRowState: Identifiable, Equatable {
    var id: String
    var title: String
    var fireDate: Date
    var kind: ReminderKind
}

struct DueSoonRowState: Identifiable, Equatable {
    var id: UUID
    var name: String
    var money: Money
    var dueDate: Date
    var subtitle: String
    var status: SubscriptionStatus
    var iconName: String
}

struct AmortizedDetailRowState: Identifiable, Equatable {
    var id: UUID
    var name: String
    var categoryName: String
    var money: Money
    var iconName: String
}

struct HomeSummaryCardState: Identifiable, Equatable {
    var id: String
    var title: String
    var money: Money?
    var count: Int?
    var detailRows: [AmortizedDetailRowState]

    static func money(_ id: String, title: String, money: Money?, detailRows: [AmortizedDetailRowState] = []) -> HomeSummaryCardState {
        HomeSummaryCardState(id: id, title: title, money: money, count: nil, detailRows: detailRows)
    }

    static func count(_ id: String, title: String, count: Int) -> HomeSummaryCardState {
        HomeSummaryCardState(id: id, title: title, money: nil, count: count, detailRows: [])
    }
}

enum HomeQuickAction: String, CaseIterable, Identifiable {
    case addSubscription
    case viewStatistics
    case backupRestore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addSubscription: "新增"
        case .viewStatistics: "统计"
        case .backupRestore: "备份"
        }
    }

    var systemImage: String {
        switch self {
        case .addSubscription: "plus.circle"
        case .viewStatistics: "chart.pie"
        case .backupRestore: "externaldrive"
        }
    }
}

enum HomeSubscriptionScope: String, CaseIterable, Identifiable {
    case active
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "活跃"
        case .history: "历史"
        }
    }
}

struct HomeDashboardViewState: Equatable {
    var summaryCards: [HomeSummaryCardState]
    var monthTotal: Money?
    var yearTotal: Money?
    var activeCount: Int
    var upcoming30Days: Money?
    var hasAnySubscriptions: Bool
    var subscriptionRows: [SubscriptionRowState]
    var dueSoonRows: [DueSoonRowState]
    var quickActions: [HomeQuickAction]
    var subscriptionScope: HomeSubscriptionScope
    var isStatisticsIncomplete: Bool
    var incompleteReason: String?

    static let empty = HomeDashboardViewState(
        summaryCards: [],
        monthTotal: nil,
        yearTotal: nil,
        activeCount: 0,
        upcoming30Days: nil,
        hasAnySubscriptions: false,
        subscriptionRows: [],
        dueSoonRows: [],
        quickActions: HomeQuickAction.allCases,
        subscriptionScope: .active,
        isStatisticsIncomplete: false,
        incompleteReason: nil
    )
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var state: HomeDashboardViewState = .empty
    @Published var errorMessage: String?

    private let subscriptions: SubscriptionRepository
    private let categories: CategoryRepository
    private let templates: ServiceTemplateRepository
    private let exchangeRates: ExchangeRateRepository
    private let settings: AppSettingsRepository
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        subscriptions: SubscriptionRepository,
        categories: CategoryRepository,
        templates: ServiceTemplateRepository,
        exchangeRates: ExchangeRateRepository,
        settings: AppSettingsRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.subscriptions = subscriptions
        self.categories = categories
        self.templates = templates
        self.exchangeRates = exchangeRates
        self.settings = settings
        self.calendar = calendar
        self.nowProvider = now
    }

    func load(subscriptionScope: HomeSubscriptionScope? = nil) {
        do {
            let subscriptionQuery = SubscriptionQueryService(repository: subscriptions)
            let allRecords = try subscriptionQuery.all()
            let activeRecords = allRecords.filter(\.status.isOngoing)
            let historyRecords = allRecords.filter { !$0.status.isOngoing }
            let categoryMap = Dictionary(uniqueKeysWithValues: try categories.fetchAll(includeArchived: true).map { ($0.id, $0.name) })
            let templateIconMap = Dictionary(uniqueKeysWithValues: try templates.fetchAll().map { ($0.serviceKey, $0.iconStyle.systemName) })
            let appSettings = try settings.fetch()
            let converter = CurrencyConverter(rates: try exchangeRates.fetchAll(), calendar: calendar)
            let resolver = BillingScheduleResolver(calendar: calendar)
            let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: calendar)
            let now = nowProvider()
            let monthRange = try currentMonthRange(containing: now)
            let yearRange = try currentYearRange(containing: now)
            let upcomingRange = try DateRange(start: calendar.startOfDay(for: now), endExclusive: calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: now))!)
            let month = engine.amortizedTotal(records: allRecords, range: monthRange, displayCurrency: appSettings.primaryDisplayCurrency, scope: .monthly)
            let year = engine.amortizedTotal(records: allRecords, range: yearRange, displayCurrency: appSettings.primaryDisplayCurrency, scope: .yearly(cutoff: now))
            let upcoming = engine.amortizedTotal(records: activeRecords, range: upcomingRange, displayCurrency: appSettings.primaryDisplayCurrency)
            let selectedScope = subscriptionScope ?? state.subscriptionScope
            let visibleRecords = selectedScope == .active ? activeRecords : historyRecords
            let rows = sortedRows(visibleRecords.map {
                let dateInfo = displayDate(for: $0, resolver: resolver, now: now)
                return SubscriptionRowState(
                    id: $0.id,
                    name: $0.serviceName,
                    money: $0.effectiveMoney,
                    status: $0.status,
                    categoryName: categoryMap[$0.categoryId] ?? "其他",
                    billingCycleName: $0.billingCycle.displayName,
                    displayDate: dateInfo?.date,
                    displayDateLabel: dateInfo?.label,
                    iconName: templateIconMap[$0.serviceKey] ?? "creditcard"
                )
            })
            let dueSoonRows = activeRecords.compactMap { record -> DueSoonRowState? in
                guard let due = dueSoonDate(for: record, resolver: resolver, now: now) else { return nil }
                let dueDate = due.date
                guard dueDate >= calendar.startOfDay(for: now), dueDate <= upcomingRange.endExclusive else { return nil }
                return DueSoonRowState(
                    id: record.id,
                    name: record.serviceName,
                    money: record.effectiveMoney,
                    dueDate: dueDate,
                    subtitle: due.label,
                    status: record.status,
                    iconName: templateIconMap[record.serviceKey] ?? "calendar"
                )
            }
            .sorted { $0.dueDate < $1.dueDate }
            let monthDetails = amortizedDetails(
                records: allRecords,
                range: monthRange,
                engine: engine,
                displayCurrency: appSettings.primaryDisplayCurrency,
                categoryMap: categoryMap,
                templateIconMap: templateIconMap,
                scope: .monthly
            )
            let yearDetails = amortizedDetails(
                records: allRecords,
                range: yearRange,
                engine: engine,
                displayCurrency: appSettings.primaryDisplayCurrency,
                categoryMap: categoryMap,
                templateIconMap: templateIconMap,
                scope: .yearly(cutoff: now)
            )

            let missing = Array(Set(month.missingRates + year.missingRates + upcoming.missingRates)).sorted()
            let summaryCards: [HomeSummaryCardState] = [
                .money("month", title: "本月已摊销", money: month.total, detailRows: monthDetails),
                .money("year", title: "今年已摊销", money: year.total, detailRows: yearDetails),
                .count("active", title: "活跃订阅", count: activeRecords.count)
            ]
            state = HomeDashboardViewState(
                summaryCards: summaryCards,
                monthTotal: month.total,
                yearTotal: year.total,
                activeCount: activeRecords.count,
                upcoming30Days: upcoming.total,
                hasAnySubscriptions: !allRecords.isEmpty,
                subscriptionRows: rows,
                dueSoonRows: dueSoonRows,
                quickActions: HomeQuickAction.allCases,
                subscriptionScope: selectedScope,
                isStatisticsIncomplete: !missing.isEmpty,
                incompleteReason: missing.isEmpty ? nil : "需要补充汇率：\(missing.joined(separator: ", "))"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortedRows(_ rows: [SubscriptionRowState]) -> [SubscriptionRowState] {
        rows.sorted {
            let lhsDate = $0.displayDate ?? .distantFuture
            let rhsDate = $1.displayDate ?? .distantFuture
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func displayDate(
        for record: SubscriptionRecord,
        resolver: BillingScheduleResolver,
        now: Date
    ) -> (date: Date, label: String)? {
        let endDateInfo = record.endDate.map { ($0, record.status.isOngoing ? "结束" : "已结束") }
        if record.status.allowsFutureBillingReminder,
           let nextBillingDate = (try? resolver.nextBillingDate(for: record, after: now)) ?? record.nextBillingDate,
           !shouldPreferEndDate(record.endDate, over: nextBillingDate) {
            return (nextBillingDate, record.status == .trial ? "试用到期" : "下次扣费")
        }
        if let endDateInfo {
            return endDateInfo
        }
        return nil
    }

    private func dueSoonDate(
        for record: SubscriptionRecord,
        resolver: BillingScheduleResolver,
        now: Date
    ) -> (date: Date, label: String)? {
        let today = calendar.startOfDay(for: now)
        var candidates: [(date: Date, label: String)] = []
        if let nextBillingDate = (try? resolver.nextBillingDate(for: record, after: now)) ?? record.nextBillingDate,
           calendar.startOfDay(for: nextBillingDate) >= today {
            candidates.append((nextBillingDate, record.status == .trial ? "试用到期" : "订阅扣费"))
        }
        if let endDate = record.endDate, calendar.startOfDay(for: endDate) >= today {
            candidates.append((endDate, record.status == .trial ? "试用到期" : "订阅到期"))
        }
        return candidates.sorted {
            if calendar.startOfDay(for: $0.date) == calendar.startOfDay(for: $1.date) {
                return $0.label.contains("到期")
            }
            return $0.date < $1.date
        }.first
    }

    private func shouldPreferEndDate(_ endDate: Date?, over nextBillingDate: Date) -> Bool {
        guard let endDate else { return false }
        return calendar.startOfDay(for: endDate) <= calendar.startOfDay(for: nextBillingDate)
    }

    private func amortizedDetails(
        records: [SubscriptionRecord],
        range: DateRange,
        engine: StatisticsEngine,
        displayCurrency: CurrencyCode,
        categoryMap: [UUID: String],
        templateIconMap: [String: String],
        scope: AmortizationScope
    ) -> [AmortizedDetailRowState] {
        records.compactMap { record in
            let result = engine.amortizedTotal(records: [record], range: range, displayCurrency: displayCurrency, scope: scope)
            guard let money = result.total, money.amount > 0 else { return nil }
            return AmortizedDetailRowState(
                id: record.id,
                name: record.serviceName,
                categoryName: categoryMap[record.categoryId] ?? "其他",
                money: money,
                iconName: templateIconMap[record.serviceKey] ?? "creditcard"
            )
        }
        .sorted { $0.money.amount > $1.money.amount }
    }

    private func currentMonthRange(containing date: Date) throws -> DateRange {
        let interval = calendar.dateInterval(of: .month, for: date)!
        return try DateRange(start: interval.start, endExclusive: interval.end)
    }

    private func currentYearRange(containing date: Date) throws -> DateRange {
        let interval = calendar.dateInterval(of: .year, for: date)!
        return try DateRange(start: interval.start, endExclusive: interval.end)
    }
}
