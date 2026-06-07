import XCTest
@testable import Subly

final class ReminderPlanGeneratorTests: XCTestCase {
    func testDefaultReminderIsOneDayBeforeBilling() throws {
        let resolver = BillingScheduleResolver(calendar: fixedCalendar())
        let generator = ReminderPlanGenerator(scheduleResolver: resolver, calendar: fixedCalendar())
        let record = sampleRecord(start: date("2026-01-10"))
        let plans = try generator.plans(for: record, defaultConfig: .defaultEnabled, now: date("2026-01-01"))
        XCTAssertEqual(plans.first?.fireDate, date("2026-01-09"))
    }

    func testCancelledRecordHasNoReminder() throws {
        let generator = ReminderPlanGenerator(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), calendar: fixedCalendar())
        let plans = try generator.plans(for: sampleRecord(status: .cancelled), defaultConfig: .defaultEnabled, now: date("2026-01-01"))
        XCTAssertTrue(plans.isEmpty)
    }

    func testMultipleOffsetsGenerateMultiplePlans() throws {
        let generator = ReminderPlanGenerator(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), calendar: fixedCalendar())
        var record = sampleRecord(start: date("2026-01-10"))
        record.reminderConfig = ReminderConfig(isEnabled: true, offsets: [.sameDay, .threeDaysBefore])

        let plans = try generator.plans(for: record, defaultConfig: .defaultEnabled, now: date("2026-01-01"))

        XCTAssertEqual(plans.map(\.fireDate).sorted(), [date("2026-01-07"), date("2026-01-10")])
    }

    func testSubscriptionCanInheritGlobalReminderConfig() throws {
        let generator = ReminderPlanGenerator(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), calendar: fixedCalendar())
        var record = sampleRecord(start: date("2026-01-10"))
        record.reminderConfig = ReminderConfig(isEnabled: true, usesGlobalDefault: true, offsets: [.sevenDaysBefore])

        let plans = try generator.plans(for: record, defaultConfig: ReminderConfig(isEnabled: true, daysBefore: 3), now: date("2026-01-01"))

        XCTAssertEqual(plans.first?.fireDate, date("2026-01-07"))
    }

    func testNegativeReminderOffsetFailsValidation() throws {
        let generator = ReminderPlanGenerator(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), calendar: fixedCalendar())
        let config = ReminderConfig(isEnabled: true, offsets: [ReminderOffset(daysBefore: -1)])

        XCTAssertThrowsError(try generator.plans(for: sampleRecord(start: date("2026-01-10")), defaultConfig: config, now: date("2026-01-01")))
    }
}
