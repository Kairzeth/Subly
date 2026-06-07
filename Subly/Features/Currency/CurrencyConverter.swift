import Foundation

@MainActor
protocol ExchangeRateProvider {
    func fetchRate(base: CurrencyCode, target: CurrencyCode, date: Date) async throws -> ExchangeRate
}

struct CurrencyConverter {
    var rates: [ExchangeRate]
    var calendar: Calendar

    init(rates: [ExchangeRate], calendar: Calendar = .current) {
        self.rates = rates
        self.calendar = calendar
    }

    func convert(_ money: Money, to target: CurrencyCode, on date: Date) throws -> Money {
        if money.currency == target {
            return Money(unchecked: money.amount, currency: target)
        }
        guard let rate = bestRate(base: money.currency, target: target, on: date) else {
            throw SublyError.missingExchangeRate(base: money.currency, target: target)
        }
        return Money(unchecked: money.amount * rate.rate, currency: target)
    }

    func bestRate(base: CurrencyCode, target: CurrencyCode, on date: Date) -> ExchangeRate? {
        let candidates = rates.filter {
            $0.baseCurrency == base &&
            $0.targetCurrency == target &&
            calendar.startOfDay(for: $0.date) <= calendar.startOfDay(for: date)
        }
        return candidates.sorted {
            if $0.isManual != $1.isManual { return $0.isManual && !$1.isManual }
            return $0.date > $1.date
        }.first
    }
}

struct FrankfurterExchangeRateProvider: ExchangeRateProvider {
    var session: URLSession = .shared

    func fetchRate(base: CurrencyCode, target: CurrencyCode, date: Date) async throws -> ExchangeRate {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")!
        components.queryItems = [
            URLQueryItem(name: "base", value: base.rawValue),
            URLQueryItem(name: "quotes", value: target.rawValue),
            URLQueryItem(name: "date", value: formatter.string(from: date))
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SublyError.network("Frankfurter returned HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode([FrankfurterRateResponse].self, from: data)
        guard let row = decoded.first(where: { $0.base == base.rawValue && $0.quote == target.rawValue }) else {
            throw SublyError.missingExchangeRate(base: base, target: target)
        }
        let effectiveDate = formatter.date(from: row.date) ?? date
        let now = Date()
        return ExchangeRate(
            id: UUID(),
            baseCurrency: base,
            targetCurrency: target,
            rate: row.rate,
            source: .frankfurter,
            date: effectiveDate,
            isManual: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct FrankfurterRateResponse: Decodable {
    var date: String
    var base: String
    var quote: String
    var rate: Decimal
}
