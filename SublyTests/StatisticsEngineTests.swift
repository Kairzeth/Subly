import XCTest
@testable import Subly

final class StatisticsEngineTests: XCTestCase {
    func testMonthlyAmortizedTotalUsesRealCoveredDays() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [sampleRate(rate: 7)], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-01-31"), calendar: fixedCalendar())
        let result = engine.amortizedTotal(records: [sampleRecord(amount: 10, cycle: .monthly)], range: range, displayCurrency: .CNY)
        XCTAssertFalse(result.isIncomplete)
        XCTAssertEqual(result.total?.amount, 70)
    }

    func testMissingRateMarksStatisticsIncomplete() throws {
        let engine = StatisticsEngine(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), converter: CurrencyConverter(rates: [], calendar: fixedCalendar()), calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-01-31"), calendar: fixedCalendar())
        let result = engine.amortizedTotal(records: [sampleRecord()], range: range, displayCurrency: .CNY)
        XCTAssertTrue(result.isIncomplete)
        XCTAssertNil(result.total)
    }
}
