import XCTest
@testable import Subly

@MainActor
final class ReminderSyncServiceTests: XCTestCase {
    func testSyncCancelsOldNotificationsBeforeSchedulingNewPlans() async throws {
        let record = sampleRecord(start: date("2026-01-10"))
        let scheduler = MockNotificationScheduler(status: .authorized)
        let service = makeService(records: [record], scheduler: scheduler)

        try await service.sync(record: record, now: date("2026-01-01"))

        XCTAssertEqual(scheduler.cancelledRecordIds, [record.id])
        XCTAssertEqual(scheduler.scheduledPlanIds.count, 1)
    }

    func testNotificationPermissionDeniedDoesNotBlockInAppPlans() async throws {
        let record = sampleRecord(start: date("2026-01-10"))
        let scheduler = MockNotificationScheduler(status: .denied)
        let service = makeService(records: [record], scheduler: scheduler)
        let query = ReminderQueryService(
            subscriptions: InMemorySubscriptionRepository(records: [record]),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            generator: ReminderPlanGenerator(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), calendar: fixedCalendar())
        )

        do {
            try await service.sync(record: record, now: date("2026-01-01"))
            XCTFail("Denied notification permission should throw.")
        } catch SublyError.notificationPermissionDenied {
            let plans = try query.plans(days: 30, now: date("2026-01-01"))
            XCTAssertEqual(plans.count, 1)
            XCTAssertTrue(scheduler.scheduledPlanIds.isEmpty)
        }
    }

    func testRebuildAllCancelsAllSchedulesAndClearsBadge() async throws {
        let records = [
            sampleRecord(name: "A", serviceKey: "a", start: date("2026-01-10")),
            sampleRecord(name: "B", serviceKey: "b", start: date("2026-01-11"))
        ]
        let scheduler = MockNotificationScheduler(status: .authorized)
        let service = makeService(records: records, scheduler: scheduler)

        try await service.rebuildAll(now: date("2026-01-01"))

        XCTAssertEqual(scheduler.cancelAllCount, 1)
        XCTAssertEqual(scheduler.scheduledPlanIds.count, 2)
        XCTAssertEqual(scheduler.badgeCounts, [0])
    }

    func testRequestPermissionAsksEvenWithoutReminderPlans() async throws {
        let scheduler = MockNotificationScheduler(status: .notDetermined)
        let service = makeService(records: [], scheduler: scheduler)

        let status = try await service.requestPermission()

        XCTAssertEqual(status, .authorized)
        XCTAssertEqual(scheduler.requestAuthorizationCount, 1)
    }

    private func makeService(records: [SubscriptionRecord], scheduler: MockNotificationScheduler) -> ReminderSyncService {
        ReminderSyncService(
            subscriptions: InMemorySubscriptionRepository(records: records),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            scheduler: scheduler,
            generator: ReminderPlanGenerator(scheduleResolver: BillingScheduleResolver(calendar: fixedCalendar()), calendar: fixedCalendar())
        )
    }
}

final class MockNotificationScheduler: LocalNotificationScheduling {
    var status: NotificationPermissionStatus
    var scheduledPlanIds: [String] = []
    var cancelledRecordIds: [UUID] = []
    var cancelAllCount = 0
    var badgeCounts: [Int] = []
    var requestAuthorizationCount = 0

    init(status: NotificationPermissionStatus) {
        self.status = status
    }

    func authorizationStatus() async -> NotificationPermissionStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCount += 1
        status = .authorized
        return true
    }

    func schedule(plans: [ReminderPlan]) async throws {
        scheduledPlanIds.append(contentsOf: plans.map(\.id))
    }

    func cancel(recordId: UUID) async {
        cancelledRecordIds.append(recordId)
    }

    func cancelAll() async {
        cancelAllCount += 1
    }

    func setBadgeCount(_ count: Int) async {
        badgeCounts.append(count)
    }
}
