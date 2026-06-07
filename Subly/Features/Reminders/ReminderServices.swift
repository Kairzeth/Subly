import Foundation
import UserNotifications
import UIKit

enum NotificationPermissionStatus: String, Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case unknown
}

@MainActor
protocol LocalNotificationScheduling {
    func authorizationStatus() async -> NotificationPermissionStatus
    func requestAuthorization() async throws -> Bool
    func schedule(plans: [ReminderPlan]) async throws
    func cancel(recordId: UUID) async
    func cancelAll() async
    func setBadgeCount(_ count: Int) async
}

struct UserNotificationScheduler: LocalNotificationScheduling {
    var center: UNUserNotificationCenter = .current()

    func authorizationStatus() async -> NotificationPermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func schedule(plans: [ReminderPlan]) async throws {
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.badge = NSNumber(value: plan.badgeDelta)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
        }
    }

    func cancel(recordId: UUID) async {
        let prefix = recordId.uuidString
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func setBadgeCount(_ count: Int) async {
        if #available(iOS 17.0, *) {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        } else {
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }
}

@MainActor
struct ReminderQueryService {
    var subscriptions: SubscriptionRepository
    var settings: AppSettingsRepository
    var generator: ReminderPlanGenerator

    func plans(days: Int, now: Date = Date()) throws -> [ReminderPlan] {
        let appSettings = try settings.fetch()
        let end = generator.calendar.date(byAdding: .day, value: days, to: generator.calendar.startOfDay(for: now))!
        return try subscriptions.fetchAll()
            .flatMap { try generator.plans(for: $0, defaultConfig: appSettings.defaultReminderConfig, now: now) }
            .filter { $0.fireDate <= end }
            .sorted { $0.fireDate < $1.fireDate }
    }

    func badgeCount(days: Int = 30, now: Date = Date()) throws -> Int {
        try plans(days: days, now: now).count
    }
}

@MainActor
struct ReminderSyncService {
    var subscriptions: SubscriptionRepository
    var settings: AppSettingsRepository
    var scheduler: LocalNotificationScheduling
    var generator: ReminderPlanGenerator

    func sync(record: SubscriptionRecord, now: Date = Date()) async throws {
        await scheduler.cancel(recordId: record.id)
        let appSettings = try settings.fetch()
        let plans = try generator.plans(for: record, defaultConfig: appSettings.defaultReminderConfig, now: now)
        try await scheduleIfAllowed(plans)
    }

    func cancel(recordId: UUID) async {
        await scheduler.cancel(recordId: recordId)
    }

    func rebuildAll(now: Date = Date()) async throws {
        await scheduler.cancelAll()
        let appSettings = try settings.fetch()
        let plans = try subscriptions.fetchAll()
            .flatMap { try generator.plans(for: $0, defaultConfig: appSettings.defaultReminderConfig, now: now) }
        try await scheduleIfAllowed(plans)
        await scheduler.setBadgeCount(plans.reduce(0) { $0 + max(0, $1.badgeDelta) })
    }

    func permissionStatus() async -> NotificationPermissionStatus {
        await scheduler.authorizationStatus()
    }

    func requestPermission() async throws -> NotificationPermissionStatus {
        let status = await scheduler.authorizationStatus()
        switch status {
        case .authorized, .provisional:
            return status
        case .notDetermined:
            if try await scheduler.requestAuthorization() {
                return await scheduler.authorizationStatus()
            } else {
                throw SublyError.notificationPermissionDenied
            }
        case .denied, .unknown:
            throw SublyError.notificationPermissionDenied
        }
    }

    private func scheduleIfAllowed(_ plans: [ReminderPlan]) async throws {
        guard !plans.isEmpty else { return }
        let status = await scheduler.authorizationStatus()
        switch status {
        case .authorized, .provisional:
            try await scheduler.schedule(plans: plans)
        case .notDetermined:
            if try await scheduler.requestAuthorization() {
                try await scheduler.schedule(plans: plans)
            } else {
                throw SublyError.notificationPermissionDenied
            }
        case .denied, .unknown:
            throw SublyError.notificationPermissionDenied
        }
    }
}
