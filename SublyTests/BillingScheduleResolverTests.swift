import XCTest
@testable import Subly

final class BillingScheduleResolverTests: XCTestCase {
    func testYearlySubscriptionIsProratedAcrossPartialServiceWindow() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let record = sampleRecord(amount: 120, cycle: .yearly, start: date("2026-03-01"), end: date("2026-06-30"))
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-12-31"), calendar: fixedCalendar())
        let occurrences = try resolver.occurrences(for: record, in: range)
        XCTAssertEqual(occurrences.first?.intersectedDays, 122)
        XCTAssertEqual(occurrences.first?.totalCycleDays, 365)
    }

    func testPausedRecordKeepsHistoricalCoverageBeforeEndDate() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let record = sampleRecord(cycle: .monthly, start: date("2026-01-01"), end: date("2026-01-10"), status: .paused)
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-02-01"), calendar: fixedCalendar())
        let occurrences = try resolver.occurrences(for: record, in: range)
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.intersectedDays, 10)
    }

    func testPausedRecordGeneratesNoFutureBillingDate() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let record = sampleRecord(status: .paused)
        XCTAssertNil(try resolver.nextBillingDate(for: record, after: date("2026-01-01")))
    }

    func testManualNextBillingDateWins() throws {
        var record = sampleRecord(start: date("2026-01-01"))
        record.nextBillingDate = date("2026-02-14")
        record.isNextBillingDateManual = true
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        XCTAssertEqual(try resolver.nextBillingDate(for: record, after: date("2026-01-10")), date("2026-02-14"))
    }

    func testOneTimeWithoutEndDateThrows() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let record = sampleRecord(cycle: .oneTime)
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-02-01"), calendar: fixedCalendar())
        XCTAssertThrowsError(try resolver.occurrences(for: record, in: range))
    }
}
