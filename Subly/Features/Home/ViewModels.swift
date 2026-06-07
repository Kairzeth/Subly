import Foundation

struct SubscriptionRowState: Identifiable, Equatable {
    var id: UUID
    var name: String
    var money: Money
    var status: SubscriptionStatus
    var categoryName: String
    var billingCycleName: String
    var nextBillingDate: Date?
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
    var status: SubscriptionStatus
    var iconName: String
}

struct HomeSummaryCardState: Identifiable, Equatable {
    var id: String
    var title: String
    var money: Money?
    var count: Int?

    static func money(_ id: String, title: String, money: Money?) -> HomeSummaryCardState {
        HomeSummaryCardState(id: id, title: title, money: money, count: nil)
    }

    static func count(_ id: String, title: String, count: Int) -> HomeSummaryCardState {
        HomeSummaryCardState(id: id, title: title, money: nil, count: count)
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

    init(
        subscriptions: SubscriptionRepository,
        categories: CategoryRepository,
        templates: ServiceTemplateRepository,
        exchangeRates: ExchangeRateRepository,
        settings: AppSettingsRepository,
        calendar: Calendar = .current
    ) {
        self.subscriptions = subscriptions
        self.categories = categories
        self.templates = templates
        self.exchangeRates = exchangeRates
        self.settings = settings
        self.calendar = calendar
    }

    func load(subscriptionScope: HomeSubscriptionScope? = nil) {
        do {
            let subscriptionQuery = SubscriptionQueryService(repository: subscriptions)
            let allRecords = try subscriptionQuery.all()
            let activeRecords = allRecords.filter { $0.status == .active || $0.status == .trial }
            let historyRecords = allRecords.filter { !($0.status == .active || $0.status == .trial) }
            let categoryMap = Dictionary(uniqueKeysWithValues: try categories.fetchAll(includeArchived: true).map { ($0.id, $0.name) })
            let templateIconMap = Dictionary(uniqueKeysWithValues: try templates.fetchAll().map { ($0.serviceKey, $0.iconStyle.systemName) })
            let appSettings = try settings.fetch()
            let converter = CurrencyConverter(rates: try exchangeRates.fetchAll(), calendar: calendar)
            let resolver = BillingScheduleResolver(calendar: calendar)
            let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: calendar)
            let now = Date()
            let monthRange = try currentMonthRange(containing: now)
            let yearRange = try currentYearRange(containing: now)
            let upcomingRange = try DateRange(start: calendar.startOfDay(for: now), endExclusive: calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: now))!)
            let month = engine.billedTotal(records: allRecords, range: monthRange, displayCurrency: appSettings.primaryDisplayCurrency)
            let year = engine.billedTotal(records: allRecords, range: yearRange, displayCurrency: appSettings.primaryDisplayCurrency)
            let upcoming = engine.amortizedTotal(records: activeRecords, range: upcomingRange, displayCurrency: appSettings.primaryDisplayCurrency)
            let selectedScope = subscriptionScope ?? state.subscriptionScope
            let visibleRecords = selectedScope == .active ? activeRecords : historyRecords
            let rows = sortedRows(visibleRecords.map {
                SubscriptionRowState(
                    id: $0.id,
                    name: $0.serviceName,
                    money: $0.effectiveMoney,
                    status: $0.status,
                    categoryName: categoryMap[$0.categoryId] ?? "其他",
                    billingCycleName: $0.billingCycle.displayName,
                    nextBillingDate: (try? resolver.nextBillingDate(for: $0, after: now)) ?? $0.nextBillingDate,
                    iconName: templateIconMap[$0.serviceKey] ?? "creditcard"
                )
            })
            let dueSoonRows = activeRecords.compactMap { record -> DueSoonRowState? in
                guard let dueDate = (try? resolver.nextBillingDate(for: record, after: now)) ?? record.nextBillingDate else { return nil }
                guard dueDate >= calendar.startOfDay(for: now), dueDate <= upcomingRange.endExclusive else { return nil }
                return DueSoonRowState(
                    id: record.id,
                    name: record.serviceName,
                    money: record.effectiveMoney,
                    dueDate: dueDate,
                    status: record.status,
                    iconName: templateIconMap[record.serviceKey] ?? "calendar"
                )
            }
            .sorted { $0.dueDate < $1.dueDate }

            let missing = Array(Set(month.missingRates + year.missingRates + upcoming.missingRates)).sorted()
            let summaryCards: [HomeSummaryCardState] = [
                .money("month", title: "本月累计", money: month.total),
                .money("year", title: "本年累计", money: year.total),
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
            let lhsDate = $0.nextBillingDate ?? .distantFuture
            let rhsDate = $1.nextBillingDate ?? .distantFuture
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
