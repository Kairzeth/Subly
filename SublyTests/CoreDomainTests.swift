import XCTest
@testable import Subly

final class CoreDomainTests: XCTestCase {
    func testCustomDaysRejectsNonPositiveValues() throws {
        XCTAssertThrowsError(try BillingCycle.customDays(0).validate())
        XCTAssertThrowsError(try BillingCycle.customDays(-3).validate())
    }

    func testPrimaryDisplayCurrencyIsCNYOrUSDOnly() throws {
        XCTAssertNoThrow(try CurrencyCode.validatePrimaryDisplayCurrency(.CNY))
        XCTAssertNoThrow(try CurrencyCode.validatePrimaryDisplayCurrency(.USD))
        XCTAssertThrowsError(try CurrencyCode.validatePrimaryDisplayCurrency(.EUR))
    }

    func testSupportedSubscriptionCurrencies() {
        XCTAssertEqual(Set(CurrencyCode.allCases), [.CNY, .USD, .HKD, .JPY, .EUR, .GBP])
    }

    func testMoneyRejectsNegativeAmounts() {
        XCTAssertThrowsError(try Money(amount: -1, currency: .CNY))
    }

    func testDateRangeUsesHalfOpenEnd() throws {
        let range = try DateRange.fromUserDates(start: date("2026-01-01"), inclusiveEnd: date("2026-01-01"), calendar: fixedCalendar())
        XCTAssertEqual(range.coveredDays(calendar: fixedCalendar()), 1)
    }

    func testLeapYearAndCrossYearDays() throws {
        let leap = try DateRange.fromUserDates(start: date("2024-02-28"), inclusiveEnd: date("2024-03-01"), calendar: fixedCalendar())
        XCTAssertEqual(leap.coveredDays(calendar: fixedCalendar()), 3)
        let crossYear = try DateRange.fromUserDates(start: date("2025-12-31"), inclusiveEnd: date("2026-01-01"), calendar: fixedCalendar())
        XCTAssertEqual(crossYear.coveredDays(calendar: fixedCalendar()), 2)
    }

    func testStatusReminderEligibility() {
        XCTAssertTrue(SubscriptionStatus.active.allowsFutureBillingReminder)
        XCTAssertTrue(SubscriptionStatus.trial.allowsFutureBillingReminder)
        XCTAssertTrue(SubscriptionStatus.pendingRenewalDecision.allowsFutureBillingReminder)
        XCTAssertFalse(SubscriptionStatus.paused.allowsFutureBillingReminder)
        XCTAssertFalse(SubscriptionStatus.cancelled.allowsFutureBillingReminder)
        XCTAssertFalse(SubscriptionStatus.expired.allowsFutureBillingReminder)
    }

    func testSublyErrorDescriptionIsDisplayable() {
        XCTAssertNotNil(SublyError.validation(.emptyName).errorDescription)
        XCTAssertNotNil(SublyError.missingExchangeRate(base: .USD, target: .CNY).errorDescription)
    }
}
