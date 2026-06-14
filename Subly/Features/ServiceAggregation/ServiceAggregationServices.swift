import Foundation

struct ServiceAggregationOption: Identifiable, Equatable {
    var id: String { serviceKey }
    var serviceKey: String
    var displayName: String
    var recordCount: Int
}

struct ServiceAggregationDetail: Equatable {
    var serviceKey: String
    var displayName: String
    var activeSegments: [SubscriptionRecord]
    var historySegments: [SubscriptionRecord]
    var cumulativeCost: Money?
    var isIncomplete: Bool
    var missingRates: [String]
}

@MainActor
struct ServiceAggregationQueryService {
    var subscriptions: SubscriptionRepository
    var exchangeRates: ExchangeRateRepository
    var settings: AppSettingsRepository
    var calendar: Calendar = .current

    func options(excluding recordId: UUID? = nil) throws -> [ServiceAggregationOption] {
        let records = try subscriptions.fetchAll()
            .filter { $0.id != recordId }
        return Dictionary(grouping: records, by: \.serviceKey)
            .map { serviceKey, records in
                ServiceAggregationOption(
                    serviceKey: serviceKey,
                    displayName: displayName(for: records),
                    recordCount: records.count
                )
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    func detail(serviceKey: String, now: Date = Date()) throws -> ServiceAggregationDetail {
        let records = try subscriptions.fetchByServiceKey(serviceKey)
            .sorted { $0.startDate > $1.startDate }
        let appSettings = try settings.fetch()
        let start = records.map(\.startDate).min() ?? calendar.startOfDay(for: now)
        let range = try DateRange(
            start: calendar.startOfDay(for: start),
            endExclusive: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        )
        let engine = StatisticsEngine(
            scheduleResolver: BillingScheduleResolver(calendar: calendar),
            converter: CurrencyConverter(rates: try exchangeRates.fetchAll(), calendar: calendar),
            calendar: calendar
        )
        let result = engine.amortizedTotal(records: records, range: range, displayCurrency: appSettings.primaryDisplayCurrency)

        return ServiceAggregationDetail(
            serviceKey: serviceKey,
            displayName: displayName(for: records),
            activeSegments: records.filter(\.status.isOngoing),
            historySegments: records,
            cumulativeCost: result.total,
            isIncomplete: result.isIncomplete,
            missingRates: result.missingRates
        )
    }

    private func displayName(for records: [SubscriptionRecord]) -> String {
        records.sorted {
            if $0.status.isOngoing, !$1.status.isOngoing { return true }
            if $1.status.isOngoing, !$0.status.isOngoing { return false }
            return $0.updatedAt > $1.updatedAt
        }.first?.serviceName ?? "未命名服务"
    }
}

@MainActor
struct ServiceAggregationCommandService {
    var subscriptions: SubscriptionRepository
    var keyResolver = ServiceKeyResolver()

    func move(recordId: UUID, toExistingServiceKey serviceKey: String) throws -> SubscriptionRecord {
        guard var record = try subscriptions.fetch(id: recordId) else {
            throw SublyError.persistence("Subscription not found")
        }
        record.serviceKey = serviceKey
        try subscriptions.save(record)
        return record
    }

    func createNewGroup(for recordId: UUID) throws -> SubscriptionRecord {
        guard var record = try subscriptions.fetch(id: recordId) else {
            throw SublyError.persistence("Subscription not found")
        }
        record.serviceKey = keyResolver.resolve(serviceName: record.serviceName, template: nil, history: [])
        try subscriptions.save(record)
        return record
    }
}
