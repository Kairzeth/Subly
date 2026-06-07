import XCTest
@testable import Subly

final class CurrencyConverterTests: XCTestCase {
    func testManualRateWinsWhenAvailable() throws {
        let converter = CurrencyConverter(rates: [
            sampleRate(rate: 7, date: date("2026-01-01"), manual: false),
            sampleRate(rate: 8, date: date("2026-01-01"), manual: true)
        ], calendar: fixedCalendar())
        let result = try converter.convert(Money(unchecked: 10, currency: .USD), to: .CNY, on: date("2026-01-02"))
        XCTAssertEqual(result.amount, 80)
    }

    func testMissingRateThrows() {
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        XCTAssertThrowsError(try converter.convert(Money(unchecked: 10, currency: .USD), to: .CNY, on: date("2026-01-01")))
    }

    func testFrankfurterProviderDecodesRatesEndpointArrayResponse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v2/rates")
            XCTAssertTrue(request.url?.query?.contains("base=USD") == true)
            XCTAssertTrue(request.url?.query?.contains("quotes=CNY") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = #"[{"date":"2026-06-05","base":"USD","quote":"CNY","rate":6.7683}]"#.data(using: .utf8)!
            return (response, data)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = FrankfurterExchangeRateProvider(session: URLSession(configuration: configuration))

        let rate = try await provider.fetchRate(base: .USD, target: .CNY, date: date("2026-06-05"))

        XCTAssertEqual(rate.baseCurrency, .USD)
        XCTAssertEqual(rate.targetCurrency, .CNY)
        XCTAssertEqual(rate.rate, Decimal(string: "6.7683"))
        XCTAssertEqual(rate.source, .frankfurter)
        XCTAssertEqual(rate.date, date("2026-06-05"))
    }

    @MainActor
    func testRefreshServiceFetchesMissingAutomaticRate() async throws {
        let subscriptions = InMemorySubscriptionRepository(records: [
            sampleRecord(currency: .USD)
        ])
        let rates = InMemoryExchangeRateRepository(rates: [])
        let provider = MockExchangeRateProvider(rates: [
            "USD-CNY": sampleRate(rate: Decimal(string: "7.1")!, date: date("2026-06-07"))
        ])
        let service = ExchangeRateRefreshService(
            subscriptions: subscriptions,
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-06-07"))),
            exchangeRates: rates,
            provider: provider,
            calendar: fixedCalendar()
        )

        let summary = await service.refreshToday(now: date("2026-06-07"))

        XCTAssertEqual(summary.requestedPairs, 1)
        XCTAssertEqual(summary.refreshedPairs, 1)
        XCTAssertEqual(rates.rates.count, 1)
        XCTAssertEqual(rates.rates.first?.rate, Decimal(string: "7.1"))
    }

    @MainActor
    func testRefreshServiceSkipsExistingAutomaticRateUnlessForced() async throws {
        let existing = sampleRate(rate: 7, date: date("2026-06-07"))
        let rates = InMemoryExchangeRateRepository(rates: [existing])
        let provider = MockExchangeRateProvider(rates: [
            "USD-CNY": sampleRate(rate: 8, date: date("2026-06-07"))
        ])
        let service = ExchangeRateRefreshService(
            subscriptions: InMemorySubscriptionRepository(records: [sampleRecord(currency: .USD)]),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-06-07"))),
            exchangeRates: rates,
            provider: provider,
            calendar: fixedCalendar()
        )

        let skipped = await service.refreshToday(now: date("2026-06-07"))
        let forced = await service.refreshToday(now: date("2026-06-07"), force: true)

        XCTAssertEqual(skipped.skippedPairs, 1)
        XCTAssertEqual(forced.refreshedPairs, 1)
        XCTAssertEqual(rates.rates.count, 1)
        XCTAssertEqual(rates.rates.first?.id, existing.id)
        XCTAssertEqual(rates.rates.first?.rate, 8)
    }

    @MainActor
    func testRefreshServiceKeepsExistingCacheWhenProviderFails() async throws {
        let existing = sampleRate(rate: 7, date: date("2026-06-07"))
        let rates = InMemoryExchangeRateRepository(rates: [existing])
        let service = ExchangeRateRefreshService(
            subscriptions: InMemorySubscriptionRepository(records: [sampleRecord(currency: .USD)]),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-06-07"))),
            exchangeRates: rates,
            provider: MockExchangeRateProvider(error: SublyError.networkUnavailable),
            calendar: fixedCalendar()
        )

        let summary = await service.refreshToday(now: date("2026-06-07"), force: true)

        XCTAssertEqual(summary.failedPairs, ["USD-CNY"])
        XCTAssertEqual(rates.rates.count, 1)
        XCTAssertEqual(rates.rates.first, existing)
    }
}

struct MockExchangeRateProvider: ExchangeRateProvider {
    var rates: [String: ExchangeRate] = [:]
    var error: Error?

    func fetchRate(base: CurrencyCode, target: CurrencyCode, date: Date) async throws -> ExchangeRate {
        if let error {
            throw error
        }
        guard let rate = rates["\(base.rawValue)-\(target.rawValue)"] else {
            throw SublyError.missingExchangeRate(base: base, target: target)
        }
        return rate
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: SublyError.networkUnavailable)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
