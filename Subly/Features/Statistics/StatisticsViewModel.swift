import Foundation

struct CategoryCost: Identifiable, Equatable {
    var id: UUID
    var name: String
    var money: Money
}

struct ServiceCost: Identifiable, Equatable {
    var id: String
    var name: String
    var money: Money
}

struct PeriodCost: Identifiable, Equatable {
    var id: String
    var title: String
    var money: Money
}

struct StatisticsPageState: Equatable {
    var monthTotal: Money?
    var yearTotal: Money?
    var upcoming30Days: Money?
    var activeCount: Int
    var categories: [CategoryCost]
    var services: [ServiceCost]
    var monthCategories: [CategoryCost]
    var yearCategories: [CategoryCost]
    var monthServices: [ServiceCost]
    var yearServices: [ServiceCost]
    var monthlyTrend: [PeriodCost]
    var yearlyTrend: [PeriodCost]
    var isIncomplete: Bool
    var incompleteReason: String?

    static let empty = StatisticsPageState(
        monthTotal: nil,
        yearTotal: nil,
        upcoming30Days: nil,
        activeCount: 0,
        categories: [],
        services: [],
        monthCategories: [],
        yearCategories: [],
        monthServices: [],
        yearServices: [],
        monthlyTrend: [],
        yearlyTrend: [],
        isIncomplete: false,
        incompleteReason: nil
    )
}

@MainActor
struct StatisticsQueryService {
    var subscriptions: SubscriptionRepository
    var categories: CategoryRepository
    var templates: ServiceTemplateRepository? = nil
    var exchangeRates: ExchangeRateRepository
    var settings: AppSettingsRepository
    var calendar: Calendar = .current

    func pageState(now: Date = Date()) throws -> StatisticsPageState {
        let records = try subscriptions.fetchAll()
        let activeRecords = records.filter { $0.status == .active || $0.status == .trial || $0.status == .pendingRenewalDecision }
        let appSettings = try settings.fetch()
        let categoryList = try categories.fetchAll(includeArchived: true)
        let categoryNames = Dictionary(uniqueKeysWithValues: categoryList.map { ($0.id, $0.name) })
        let engine = StatisticsEngine(
            scheduleResolver: BillingScheduleResolver(calendar: calendar),
            converter: CurrencyConverter(rates: try exchangeRates.fetchAll(), calendar: calendar),
            calendar: calendar
        )
        let month = engine.billedTotal(records: records, range: try monthRange(containing: now), displayCurrency: appSettings.primaryDisplayCurrency)
        let year = engine.billedTotal(records: records, range: try yearRange(containing: now), displayCurrency: appSettings.primaryDisplayCurrency)
        let allTime = engine.billedTotal(records: records, range: try allTimeRange(endingAt: now), displayCurrency: appSettings.primaryDisplayCurrency)
        let upcoming = engine.amortizedTotal(
            records: activeRecords,
            range: try DateRange(start: calendar.startOfDay(for: now), endExclusive: calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: now))!),
            displayCurrency: appSettings.primaryDisplayCurrency
        )
        let monthCategoryCosts = categoryCosts(from: month, names: categoryNames, currency: appSettings.primaryDisplayCurrency)
        let yearCategoryCosts = categoryCosts(from: year, names: categoryNames, currency: appSettings.primaryDisplayCurrency)
        let allTimeCategoryCosts = categoryCosts(from: allTime, names: categoryNames, currency: appSettings.primaryDisplayCurrency)
        let serviceNames = serviceDisplayNames(records: records)
        let monthServiceCosts = serviceCosts(from: month, names: serviceNames, currency: appSettings.primaryDisplayCurrency)
        let yearServiceCosts = serviceCosts(from: year, names: serviceNames, currency: appSettings.primaryDisplayCurrency)
        let allTimeServiceCosts = serviceCosts(from: allTime, names: serviceNames, currency: appSettings.primaryDisplayCurrency)
        let missing = Array(Set(month.missingRates + year.missingRates + allTime.missingRates + upcoming.missingRates)).sorted()

        return StatisticsPageState(
            monthTotal: month.total,
            yearTotal: year.total,
            upcoming30Days: upcoming.total,
            activeCount: activeRecords.count,
            categories: allTimeCategoryCosts,
            services: allTimeServiceCosts,
            monthCategories: monthCategoryCosts,
            yearCategories: yearCategoryCosts,
            monthServices: monthServiceCosts,
            yearServices: yearServiceCosts,
            monthlyTrend: try monthlyTrend(records: records, engine: engine, currency: appSettings.primaryDisplayCurrency, now: now),
            yearlyTrend: try yearlyTrend(records: records, engine: engine, currency: appSettings.primaryDisplayCurrency, now: now),
            isIncomplete: !missing.isEmpty,
            incompleteReason: missing.isEmpty ? nil : "部分记录未计入：\(missing.joined(separator: ", "))"
        )
    }

    private func categoryCosts(from result: StatisticsResult, names: [UUID: String], currency: CurrencyCode) -> [CategoryCost] {
        result.categoryTotals
            .map { CategoryCost(id: $0.key, name: names[$0.key] ?? "其他", money: Money(unchecked: $0.value, currency: currency)) }
            .sorted { $0.money.amount > $1.money.amount }
    }

    private func serviceCosts(from result: StatisticsResult, names: [String: String], currency: CurrencyCode) -> [ServiceCost] {
        result.serviceTotals
            .map { ServiceCost(id: $0.key, name: names[$0.key] ?? $0.key, money: Money(unchecked: $0.value, currency: currency)) }
            .sorted { $0.money.amount > $1.money.amount }
            .prefix(8)
            .map { $0 }
    }

    private func serviceDisplayNames(records: [SubscriptionRecord]) -> [String: String] {
        let grouped = Dictionary(grouping: records, by: \.serviceKey)
        return grouped.mapValues { records in
            records.sorted {
                if $0.status == .active, $1.status != .active { return true }
                if $1.status == .active, $0.status != .active { return false }
                return $0.updatedAt > $1.updatedAt
            }.first?.serviceName ?? ""
        }
    }

    private func monthlyTrend(records: [SubscriptionRecord], engine: StatisticsEngine, currency: CurrencyCode, now: Date) throws -> [PeriodCost] {
        try (0..<6).reversed().map { offset in
            let date = calendar.date(byAdding: .month, value: -offset, to: now)!
            let range = try monthRange(containing: date)
            let result = engine.billedTotal(records: records, range: range, displayCurrency: currency)
            let components = calendar.dateComponents([.year, .month], from: date)
            let title = "\(components.year ?? 0)-\(String(format: "%02d", components.month ?? 0))"
            return PeriodCost(id: title, title: title, money: result.total ?? Money(unchecked: 0, currency: currency))
        }
    }

    private func yearlyTrend(records: [SubscriptionRecord], engine: StatisticsEngine, currency: CurrencyCode, now: Date) throws -> [PeriodCost] {
        try (0..<3).reversed().map { offset in
            let date = calendar.date(byAdding: .year, value: -offset, to: now)!
            let range = try yearRange(containing: date)
            let result = engine.billedTotal(records: records, range: range, displayCurrency: currency)
            let year = calendar.component(.year, from: date)
            return PeriodCost(id: "\(year)", title: "\(year)", money: result.total ?? Money(unchecked: 0, currency: currency))
        }
    }

    private func allTimeRange(endingAt date: Date) throws -> DateRange {
        try DateRange(
            start: Date(timeIntervalSince1970: 0),
            endExclusive: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        )
    }

    private func monthRange(containing date: Date) throws -> DateRange {
        let interval = calendar.dateInterval(of: .month, for: date)!
        return try DateRange(start: interval.start, endExclusive: interval.end)
    }

    private func yearRange(containing date: Date) throws -> DateRange {
        let interval = calendar.dateInterval(of: .year, for: date)!
        return try DateRange(start: interval.start, endExclusive: interval.end)
    }
}

@MainActor
final class StatisticsViewModel: ObservableObject {
    @Published var state: StatisticsPageState = .empty
    @Published var errorMessage: String?

    private let queryService: StatisticsQueryService

    init(queryService: StatisticsQueryService) {
        self.queryService = queryService
    }

    func load() {
        do {
            state = try queryService.pageState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
