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

    func testQuarterlyAmortizedTotalSpreadsPaymentAcrossThreeMonths() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-01-31"), calendar: fixedCalendar())
        let monthly = sampleRecord(name: "Monthly", serviceKey: "monthly", amount: 90, currency: .CNY, cycle: .monthly, start: date("2026-01-01"))
        let quarterly = sampleRecord(name: "Quarterly", serviceKey: "quarterly", amount: 90, currency: .CNY, cycle: .quarterly, start: date("2026-01-01"))

        let monthlyResult = engine.amortizedTotal(records: [monthly], range: range, displayCurrency: .CNY)
        let quarterlyResult = engine.amortizedTotal(records: [quarterly], range: range, displayCurrency: .CNY)

        XCTAssertEqual(monthlyResult.total?.amount, 90)
        XCTAssertEqual(quarterlyResult.total?.amount, 31)
    }

    func testQuarterlyAmortizedTotalProratesPartialCalendarMonth() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-15"), inclusiveEnd: date("2026-01-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 93, currency: .CNY, cycle: .quarterly, start: date("2026-01-01"))

        let result = engine.amortizedTotal(records: [record], range: range, displayCurrency: .CNY)

        XCTAssertEqual(NSDecimalNumber(decimal: result.total?.amount ?? 0).doubleValue, 17.57, accuracy: 0.01)
    }

    func testYearlyAmortizedTotalIncludesCycleStartedBeforeYear() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-12-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 365, currency: .CNY, cycle: .yearly, start: date("2025-07-01"))

        let result = engine.amortizedTotal(records: [record], range: range, displayCurrency: .CNY)

        XCTAssertFalse(result.isIncomplete)
        XCTAssertEqual(result.total?.amount, 365)
    }

    func testOpenEndedAmortizedTotalUsesFullRequestedRange() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-12-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 40, currency: .CNY, cycle: .quarterly, start: date("2025-08-12"))

        let result = engine.amortizedTotal(records: [record], range: range, displayCurrency: .CNY)

        XCTAssertFalse(result.isIncomplete)
        XCTAssertEqual(NSDecimalNumber(decimal: result.total?.amount ?? 0).doubleValue, 160, accuracy: 0.01)
    }

    func testMonthlyScopeCountsShortOneTimePaymentInBillingMonthOnly() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let juneRange = try DateRange.fromUserDates(start: date("2026-06-01"), inclusiveEnd: date("2026-06-30"), calendar: fixedCalendar())
        let julyRange = try DateRange.fromUserDates(start: date("2026-07-01"), inclusiveEnd: date("2026-07-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 135.99, currency: .CNY, cycle: .oneTime, start: date("2026-06-06"), end: date("2026-07-05"), status: .oneTime)

        let june = engine.amortizedTotal(records: [record], range: juneRange, displayCurrency: .CNY, scope: .monthly)
        let july = engine.amortizedTotal(records: [record], range: julyRange, displayCurrency: .CNY, scope: .monthly)

        XCTAssertEqual(june.total?.amount, Decimal(string: "135.99"))
        XCTAssertEqual(july.total?.amount, 0)
    }

    func testYearlyScopeCountsOnlyPaidOccurrencesUpToCutoff() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-12-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 30, currency: .CNY, cycle: .quarterly, start: date("2026-01-01"))

        let june = engine.amortizedTotal(records: [record], range: range, displayCurrency: .CNY, scope: .yearly(cutoff: date("2026-06-08")))
        let august = engine.amortizedTotal(records: [record], range: range, displayCurrency: .CNY, scope: .yearly(cutoff: date("2026-08-08")))

        XCTAssertEqual(june.total?.amount, 60)
        XCTAssertEqual(august.total?.amount, 90)
    }

    func testYearlyAmortizedTotalProratesCrossYearCycle() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-01-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 365, currency: .CNY, cycle: .yearly, start: date("2025-12-01"))

        let result = engine.amortizedTotal(records: [record], range: range, displayCurrency: .CNY)

        XCTAssertFalse(result.isIncomplete)
        XCTAssertEqual(result.total?.amount, 31)
    }

    func testOneTimeAmortizedTotalUsesFullServiceWindowAcrossYears() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-01-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 365, currency: .CNY, cycle: .oneTime, start: date("2025-07-01"), end: date("2026-06-30"), status: .oneTime)

        let result = engine.amortizedTotal(records: [record], range: range, displayCurrency: .CNY)

        XCTAssertFalse(result.isIncomplete)
        XCTAssertEqual(result.total?.amount, 31)
    }

    func testBilledTotalCountsChargeDateNotCrossYearCoverage() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let converter = CurrencyConverter(rates: [], calendar: fixedCalendar())
        let engine = StatisticsEngine(scheduleResolver: resolver, converter: converter, calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-12-31"), calendar: fixedCalendar())
        let record = sampleRecord(amount: 365, currency: .CNY, cycle: .yearly, start: date("2025-12-01"))

        let result = engine.billedTotal(records: [record], range: range, displayCurrency: .CNY)

        XCTAssertFalse(result.isIncomplete)
        XCTAssertEqual(result.total?.amount, 365)
    }

    func testMissingRateMarksStatisticsIncomplete() throws {
        let engine = StatisticsEngine(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), converter: CurrencyConverter(rates: [], calendar: fixedCalendar()), calendar: fixedCalendar())
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-01-31"), calendar: fixedCalendar())
        let result = engine.amortizedTotal(records: [sampleRecord()], range: range, displayCurrency: .CNY)
        XCTAssertTrue(result.isIncomplete)
        XCTAssertNil(result.total)
    }
}
