import Foundation

enum SublyConstants {
    static let dataVersion = 1
}

enum SubscriptionStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case paused
    case cancelled
    case trial
    case oneTime
    case expired
    case pendingRenewalDecision

    var id: String { rawValue }

    var allowsFutureBillingReminder: Bool {
        switch self {
        case .active, .trial, .pendingRenewalDecision:
            true
        case .paused, .cancelled, .oneTime, .expired:
            false
        }
    }

    var displayName: String {
        switch self {
        case .active: "活跃"
        case .paused: "已暂停"
        case .cancelled: "已取消"
        case .trial: "试用中"
        case .oneTime: "一次性"
        case .expired: "已过期"
        case .pendingRenewalDecision: "待决定"
        }
    }
}

enum BillingCycle: Codable, Equatable, Hashable {
    case weekly
    case monthly
    case quarterly
    case halfYearly
    case yearly
    case customDays(Int)
    case oneTime
    case trial(days: Int?)

    enum Kind: String, Codable {
        case weekly, monthly, quarterly, halfYearly, yearly, customDays, oneTime, trial
    }

    var kind: Kind {
        switch self {
        case .weekly: .weekly
        case .monthly: .monthly
        case .quarterly: .quarterly
        case .halfYearly: .halfYearly
        case .yearly: .yearly
        case .customDays: .customDays
        case .oneTime: .oneTime
        case .trial: .trial
        }
    }

    var displayName: String {
        switch self {
        case .weekly: "周付"
        case .monthly: "月付"
        case .quarterly: "季付"
        case .halfYearly: "半年付"
        case .yearly: "年付"
        case .customDays(let days): "\(days) 天"
        case .oneTime: "一次性"
        case .trial: "试用期"
        }
    }

    func validate() throws {
        switch self {
        case .customDays(let days) where days <= 0:
            throw ValidationError.invalidBillingCycle
        case .trial(let days?) where days <= 0:
            throw ValidationError.invalidBillingCycle
        default:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .quarterly: self = .quarterly
        case .halfYearly: self = .halfYearly
        case .yearly: self = .yearly
        case .customDays: self = .customDays(try container.decode(Int.self, forKey: .days))
        case .oneTime: self = .oneTime
        case .trial: self = .trial(days: try container.decodeIfPresent(Int.self, forKey: .days))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .customDays(let days):
            try container.encode(days, forKey: .days)
        case .trial(let days):
            try container.encodeIfPresent(days, forKey: .days)
        default:
            break
        }
    }
}

enum CurrencyCode: String, Codable, CaseIterable, Identifiable {
    case CNY, USD, HKD, JPY, EUR, GBP

    var id: String { rawValue }

    var fractionDigits: Int {
        switch self {
        case .JPY: 0
        default: 2
        }
    }

    var isPrimaryDisplayCurrency: Bool {
        self == .CNY || self == .USD
    }

    static func validatePrimaryDisplayCurrency(_ currency: CurrencyCode) throws {
        guard currency.isPrimaryDisplayCurrency else { throw ValidationError.invalidCurrency }
    }
}

struct Money: Codable, Equatable, Hashable {
    var amount: Decimal
    var currency: CurrencyCode

    init(amount: Decimal, currency: CurrencyCode) throws {
        guard amount >= 0 else { throw ValidationError.invalidAmount }
        self.amount = amount
        self.currency = currency
    }

    init(unchecked amount: Decimal, currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = currency.fractionDigits
        formatter.maximumFractionDigits = currency.fractionDigits
        let value = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        let symbol = switch currency {
        case .CNY: "¥"
        case .USD: "$"
        case .HKD: "HK$"
        case .JPY: "¥"
        case .EUR: "€"
        case .GBP: "£"
        }
        return "\(symbol)\(value)"
    }
}

struct DateRange: Codable, Equatable, Hashable {
    var start: Date
    var endExclusive: Date

    init(start: Date, endExclusive: Date) throws {
        guard endExclusive >= start else { throw ValidationError.invalidDateRange }
        self.start = start
        self.endExclusive = endExclusive
    }

    static func fromUserDates(start: Date, inclusiveEnd: Date?, calendar: Calendar = .current) throws -> DateRange {
        let normalizedStart = calendar.startOfDay(for: start)
        let end = inclusiveEnd.map { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))! }
        return try DateRange(start: normalizedStart, endExclusive: end ?? .distantFuture)
    }

    func intersection(_ other: DateRange) -> DateRange? {
        let newStart = max(start, other.start)
        let newEnd = min(endExclusive, other.endExclusive)
        guard newEnd > newStart else { return nil }
        return try? DateRange(start: newStart, endExclusive: newEnd)
    }

    func coveredDays(calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: endExclusive)
        return max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)
    }
}

struct ReminderOffset: Codable, Equatable, Hashable {
    var daysBefore: Int

    static let sameDay = ReminderOffset(daysBefore: 0)
    static let oneDayBefore = ReminderOffset(daysBefore: 1)
    static let threeDaysBefore = ReminderOffset(daysBefore: 3)
    static let sevenDaysBefore = ReminderOffset(daysBefore: 7)
}

struct ReminderConfig: Codable, Equatable, Hashable {
    var isEnabled: Bool
    var usesGlobalDefault: Bool
    var offsets: [ReminderOffset]

    init(isEnabled: Bool, usesGlobalDefault: Bool = false, offsets: [ReminderOffset]) {
        self.isEnabled = isEnabled
        self.usesGlobalDefault = usesGlobalDefault
        self.offsets = offsets.isEmpty ? [.oneDayBefore] : offsets
    }

    init(isEnabled: Bool, daysBefore: Int) {
        self.init(isEnabled: isEnabled, usesGlobalDefault: false, offsets: [ReminderOffset(daysBefore: daysBefore)])
    }

    var daysBefore: Int {
        get { offsets.first?.daysBefore ?? 1 }
        set { offsets = [ReminderOffset(daysBefore: newValue)] }
    }

    func validate() throws {
        guard offsets.allSatisfy({ $0.daysBefore >= 0 }) else {
            throw ValidationError.invalidReminderOffset
        }
    }

    static let defaultEnabled = ReminderConfig(isEnabled: true, daysBefore: 1)
}

struct SubscriptionRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var serviceName: String
    var serviceKey: String
    var categoryId: UUID
    var listedAmount: Decimal
    var listedCurrency: CurrencyCode
    var paidAmount: Decimal?
    var paidCurrency: CurrencyCode?
    var displayCurrency: CurrencyCode
    var billingCycle: BillingCycle
    var startDate: Date
    var endDate: Date?
    var nextBillingDate: Date?
    var isNextBillingDateManual: Bool
    var status: SubscriptionStatus
    var paymentMethod: String?
    var reminderConfig: ReminderConfig?
    var websiteURL: URL?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    var effectiveMoney: Money {
        Money(unchecked: paidAmount ?? listedAmount, currency: paidCurrency ?? listedCurrency)
    }
}

struct Category: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var iconName: String
    var colorToken: String
    var sortOrder: Int
    var isSystem: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct IconStyle: Codable, Equatable, Hashable {
    var systemName: String
    var colorToken: String
}

struct ServiceTemplate: Codable, Equatable, Identifiable {
    var id: UUID
    var serviceName: String
    var serviceKey: String
    var categoryId: UUID
    var defaultCurrency: CurrencyCode
    var defaultCycle: BillingCycle
    var iconStyle: IconStyle
    var note: String?
    var websiteURL: URL?
    var isSystem: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

enum ExchangeRateSource: String, Codable {
    case manual
    case frankfurter
    case mock
}

struct ExchangeRate: Codable, Equatable, Identifiable {
    var id: UUID
    var baseCurrency: CurrencyCode
    var targetCurrency: CurrencyCode
    var rate: Decimal
    var source: ExchangeRateSource
    var date: Date
    var isManual: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct AppSettings: Codable, Equatable, Identifiable {
    static let singletonId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id: UUID
    var primaryDisplayCurrency: CurrencyCode
    var defaultReminderConfig: ReminderConfig
    var followSystemAppearance: Bool
    var lastBackupAt: Date?
    var dataVersion: Int
    var createdAt: Date
    var updatedAt: Date

    static func defaults(now: Date = Date()) -> AppSettings {
        AppSettings(
            id: singletonId,
            primaryDisplayCurrency: .CNY,
            defaultReminderConfig: .defaultEnabled,
            followSystemAppearance: true,
            lastBackupAt: nil,
            dataVersion: SublyConstants.dataVersion,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct BackupMetadata: Codable, Equatable {
    var appName: String
    var appVersion: String
    var dataVersion: Int
    var createdAt: Date
    var recordCount: Int
    var checksum: String
}

protocol BackupMigrating {
    func migrate(data: Data) throws -> Data
}

struct V1BackupMigrator: BackupMigrating {
    func migrate(data: Data) throws -> Data { data }
}
