import Foundation

enum ReminderKind: String, Codable, Equatable {
    case billing
    case trialEnding
    case pendingRenewalDecision
}

struct ReminderPlan: Equatable, Identifiable {
    var id: String
    var recordId: UUID
    var kind: ReminderKind
    var fireDate: Date
    var title: String
    var body: String
    var badgeDelta: Int
}

struct ReminderPlanGenerator {
    var scheduleResolver: BillingScheduleResolving
    var calendar: Calendar

    init(scheduleResolver: BillingScheduleResolving, calendar: Calendar = .current) {
        self.scheduleResolver = scheduleResolver
        self.calendar = calendar
    }

    func plans(for record: SubscriptionRecord, defaultConfig: ReminderConfig, now: Date) throws -> [ReminderPlan] {
        let config = record.reminderConfig?.usesGlobalDefault == false ? record.reminderConfig! : defaultConfig
        try config.validate()
        guard config.isEnabled else { return [] }
        guard let candidate = try scheduleResolver.nextBillingDate(for: record, after: now) else { return [] }
        let kind: ReminderKind = switch record.status {
        case .trial: .trialEnding
        case .pendingRenewalDecision: .pendingRenewalDecision
        default: .billing
        }
        return config.offsets.compactMap { offset in
            guard let fireDate = calendar.date(byAdding: .day, value: -offset.daysBefore, to: candidate), fireDate >= now else {
                return nil
            }
            return ReminderPlan(
                id: "\(record.id.uuidString)-\(kind.rawValue)-\(offset.daysBefore)-\(Int(candidate.timeIntervalSince1970))",
                recordId: record.id,
                kind: kind,
                fireDate: fireDate,
                title: record.serviceName,
                body: "\(record.serviceName) 即将到期或扣费",
                badgeDelta: 1
            )
        }
    }
}
