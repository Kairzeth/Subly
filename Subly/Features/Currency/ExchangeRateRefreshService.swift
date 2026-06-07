import Foundation

struct ExchangeRateRefreshSummary: Equatable {
    var requestedPairs: Int
    var refreshedPairs: Int
    var skippedPairs: Int
    var failedPairs: [String]

    var hasFailures: Bool {
        !failedPairs.isEmpty
    }
}

@MainActor
struct ExchangeRateRefreshService {
    var subscriptions: SubscriptionRepository
    var settings: AppSettingsRepository
    var exchangeRates: ExchangeRateRepository
    var provider: ExchangeRateProvider
    var calendar: Calendar = .current

    func refreshToday(now: Date = Date(), force: Bool = false) async -> ExchangeRateRefreshSummary {
        let day = calendar.startOfDay(for: now)
        let pairs: [ExchangeRatePair]
        do {
            pairs = try requiredPairs(displayCurrency: settings.fetch().primaryDisplayCurrency)
        } catch {
            return ExchangeRateRefreshSummary(requestedPairs: 0, refreshedPairs: 0, skippedPairs: 0, failedPairs: ["settings"])
        }

        var refreshed = 0
        var skipped = 0
        var failed: [String] = []

        for pair in pairs {
            do {
                if !force, try cachedAutomaticRate(for: pair, on: day) != nil {
                    skipped += 1
                    continue
                }

                let fetched = try await provider.fetchRate(base: pair.base, target: pair.target, date: day)
                let existing = try cachedAutomaticRate(for: pair, on: day)
                let now = Date()
                let rate = ExchangeRate(
                    id: existing?.id ?? fetched.id,
                    baseCurrency: pair.base,
                    targetCurrency: pair.target,
                    rate: fetched.rate,
                    source: fetched.source,
                    date: calendar.startOfDay(for: fetched.date),
                    isManual: false,
                    createdAt: existing?.createdAt ?? fetched.createdAt,
                    updatedAt: now
                )
                try exchangeRates.save(rate)
                refreshed += 1
            } catch {
                failed.append(pair.id)
            }
        }

        return ExchangeRateRefreshSummary(
            requestedPairs: pairs.count,
            refreshedPairs: refreshed,
            skippedPairs: skipped,
            failedPairs: failed
        )
    }

    private func requiredPairs(displayCurrency: CurrencyCode) throws -> [ExchangeRatePair] {
        let records = try subscriptions.fetchAll()
        let currencies = Set(records.map { $0.effectiveMoney.currency })
        return currencies
            .filter { $0 != displayCurrency }
            .map { ExchangeRatePair(base: $0, target: displayCurrency) }
            .sorted { $0.id < $1.id }
    }

    private func cachedAutomaticRate(for pair: ExchangeRatePair, on date: Date) throws -> ExchangeRate? {
        try exchangeRates.fetchAll().first {
            $0.baseCurrency == pair.base &&
            $0.targetCurrency == pair.target &&
            calendar.isDate($0.date, inSameDayAs: date) &&
            !$0.isManual
        }
    }
}

private struct ExchangeRatePair: Hashable {
    var base: CurrencyCode
    var target: CurrencyCode

    var id: String {
        "\(base.rawValue)-\(target.rawValue)"
    }
}
