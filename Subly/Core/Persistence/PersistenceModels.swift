import Foundation
import SwiftData

@Model
final class SubscriptionRecordModel {
    @Attribute(.unique) var id: UUID
    var serviceName: String
    var serviceKey: String
    var categoryId: UUID
    var listedAmount: Decimal
    var listedCurrency: String
    var paidAmount: Decimal?
    var paidCurrency: String?
    var displayCurrency: String
    var billingCycleRawValue: String
    var customCycleDays: Int?
    var trialDays: Int?
    var startDate: Date
    var endDate: Date?
    var nextBillingDate: Date?
    var isNextBillingDateManual: Bool
    var statusRawValue: String
    var paymentMethod: String?
    var reminderConfigData: Data?
    var websiteURL: String?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(record: SubscriptionRecord) throws {
        id = record.id
        serviceName = record.serviceName
        serviceKey = record.serviceKey
        categoryId = record.categoryId
        listedAmount = record.listedAmount
        listedCurrency = record.listedCurrency.rawValue
        paidAmount = record.paidAmount
        paidCurrency = record.paidCurrency?.rawValue
        displayCurrency = record.displayCurrency.rawValue
        let encodedCycle = Self.encodeCycle(record.billingCycle)
        billingCycleRawValue = encodedCycle.raw
        customCycleDays = encodedCycle.customDays
        trialDays = encodedCycle.trialDays
        startDate = record.startDate
        endDate = record.endDate
        nextBillingDate = record.nextBillingDate
        isNextBillingDateManual = record.isNextBillingDateManual
        statusRawValue = record.status.rawValue
        paymentMethod = record.paymentMethod
        reminderConfigData = try record.reminderConfig.map { try JSONEncoder().encode($0) }
        websiteURL = record.websiteURL?.absoluteString
        note = record.note
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func update(from record: SubscriptionRecord) throws {
        serviceName = record.serviceName
        serviceKey = record.serviceKey
        categoryId = record.categoryId
        listedAmount = record.listedAmount
        listedCurrency = record.listedCurrency.rawValue
        paidAmount = record.paidAmount
        paidCurrency = record.paidCurrency?.rawValue
        displayCurrency = record.displayCurrency.rawValue
        let encodedCycle = Self.encodeCycle(record.billingCycle)
        billingCycleRawValue = encodedCycle.raw
        customCycleDays = encodedCycle.customDays
        trialDays = encodedCycle.trialDays
        startDate = record.startDate
        endDate = record.endDate
        nextBillingDate = record.nextBillingDate
        isNextBillingDateManual = record.isNextBillingDateManual
        statusRawValue = record.status.rawValue
        paymentMethod = record.paymentMethod
        reminderConfigData = try record.reminderConfig.map { try JSONEncoder().encode($0) }
        websiteURL = record.websiteURL?.absoluteString
        note = record.note
        createdAt = record.createdAt
        updatedAt = Date()
    }

    func domain() throws -> SubscriptionRecord {
        guard let status = SubscriptionStatus(rawValue: statusRawValue),
              let listedCurrency = CurrencyCode(rawValue: listedCurrency),
              let displayCurrency = CurrencyCode(rawValue: displayCurrency) else {
            throw SublyError.persistence("SubscriptionRecordModel decode failed")
        }
        let paidCurrencyValue = try paidCurrency.map {
            guard let value = CurrencyCode(rawValue: $0) else { throw SublyError.persistence("paidCurrency decode failed") }
            return value
        }
        let reminder = try reminderConfigData.map { try JSONDecoder().decode(ReminderConfig.self, from: $0) }
        return SubscriptionRecord(
            id: id,
            serviceName: serviceName,
            serviceKey: serviceKey,
            categoryId: categoryId,
            listedAmount: listedAmount,
            listedCurrency: listedCurrency,
            paidAmount: paidAmount,
            paidCurrency: paidCurrencyValue,
            displayCurrency: displayCurrency,
            billingCycle: Self.decodeCycle(raw: billingCycleRawValue, customDays: customCycleDays, trialDays: trialDays),
            startDate: startDate,
            endDate: endDate,
            nextBillingDate: nextBillingDate,
            isNextBillingDateManual: isNextBillingDateManual,
            status: status,
            paymentMethod: paymentMethod,
            reminderConfig: reminder,
            websiteURL: websiteURL.flatMap(URL.init(string:)),
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func encodeCycle(_ cycle: BillingCycle) -> (raw: String, customDays: Int?, trialDays: Int?) {
        switch cycle {
        case .weekly: ("weekly", nil, nil)
        case .monthly: ("monthly", nil, nil)
        case .quarterly: ("quarterly", nil, nil)
        case .halfYearly: ("halfYearly", nil, nil)
        case .yearly: ("yearly", nil, nil)
        case .customDays(let days): ("customDays", days, nil)
        case .oneTime: ("oneTime", nil, nil)
        case .trial(let days): ("trial", nil, days)
        }
    }

    static func decodeCycle(raw: String, customDays: Int?, trialDays: Int?) -> BillingCycle {
        switch raw {
        case "weekly": .weekly
        case "monthly": .monthly
        case "quarterly": .quarterly
        case "halfYearly": .halfYearly
        case "yearly": .yearly
        case "customDays": .customDays(customDays ?? 1)
        case "oneTime": .oneTime
        case "trial": .trial(days: trialDays)
        default: .monthly
        }
    }
}

@Model
final class CategoryModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String
    var colorToken: String
    var sortOrder: Int
    var isSystem: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(category: Category) {
        id = category.id
        name = category.name
        iconName = category.iconName
        colorToken = category.colorToken
        sortOrder = category.sortOrder
        isSystem = category.isSystem
        isArchived = category.isArchived
        createdAt = category.createdAt
        updatedAt = category.updatedAt
    }

    func update(from category: Category) {
        name = category.name
        iconName = category.iconName
        colorToken = category.colorToken
        sortOrder = category.sortOrder
        isSystem = category.isSystem
        isArchived = category.isArchived
        createdAt = category.createdAt
        updatedAt = Date()
    }

    func domain() -> Category {
        Category(id: id, name: name, iconName: iconName, colorToken: colorToken, sortOrder: sortOrder, isSystem: isSystem, isArchived: isArchived, createdAt: createdAt, updatedAt: updatedAt)
    }
}

@Model
final class ServiceTemplateModel {
    @Attribute(.unique) var id: UUID
    var serviceName: String
    var serviceKey: String
    var categoryId: UUID
    var defaultCurrency: String
    var defaultCycleRawValue: String
    var iconStyleData: Data
    var note: String?
    var websiteURL: String?
    var isSystem: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(template: ServiceTemplate) throws {
        id = template.id
        serviceName = template.serviceName
        serviceKey = template.serviceKey
        categoryId = template.categoryId
        defaultCurrency = template.defaultCurrency.rawValue
        defaultCycleRawValue = SubscriptionRecordModel.encodeCycle(template.defaultCycle).raw
        iconStyleData = try JSONEncoder().encode(template.iconStyle)
        note = template.note
        websiteURL = template.websiteURL?.absoluteString
        isSystem = template.isSystem
        sortOrder = template.sortOrder
        createdAt = template.createdAt
        updatedAt = template.updatedAt
    }

    func update(from template: ServiceTemplate) throws {
        serviceName = template.serviceName
        serviceKey = template.serviceKey
        categoryId = template.categoryId
        defaultCurrency = template.defaultCurrency.rawValue
        defaultCycleRawValue = SubscriptionRecordModel.encodeCycle(template.defaultCycle).raw
        iconStyleData = try JSONEncoder().encode(template.iconStyle)
        note = template.note
        websiteURL = template.websiteURL?.absoluteString
        isSystem = template.isSystem
        sortOrder = template.sortOrder
        createdAt = template.createdAt
        updatedAt = Date()
    }

    func domain() throws -> ServiceTemplate {
        ServiceTemplate(
            id: id,
            serviceName: serviceName,
            serviceKey: serviceKey,
            categoryId: categoryId,
            defaultCurrency: CurrencyCode(rawValue: defaultCurrency) ?? .CNY,
            defaultCycle: SubscriptionRecordModel.decodeCycle(raw: defaultCycleRawValue, customDays: nil, trialDays: nil),
            iconStyle: try JSONDecoder().decode(IconStyle.self, from: iconStyleData),
            note: note,
            websiteURL: websiteURL.flatMap(URL.init(string:)),
            isSystem: isSystem,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class ExchangeRateModel {
    @Attribute(.unique) var id: UUID
    var baseCurrency: String
    var targetCurrency: String
    var rate: Decimal
    var source: String
    var date: Date
    var isManual: Bool
    var createdAt: Date
    var updatedAt: Date

    init(rate: ExchangeRate) {
        id = rate.id
        baseCurrency = rate.baseCurrency.rawValue
        targetCurrency = rate.targetCurrency.rawValue
        self.rate = rate.rate
        source = rate.source.rawValue
        date = rate.date
        isManual = rate.isManual
        createdAt = rate.createdAt
        updatedAt = rate.updatedAt
    }

    func update(from rate: ExchangeRate) {
        baseCurrency = rate.baseCurrency.rawValue
        targetCurrency = rate.targetCurrency.rawValue
        self.rate = rate.rate
        source = rate.source.rawValue
        date = rate.date
        isManual = rate.isManual
        createdAt = rate.createdAt
        updatedAt = Date()
    }

    func domain() -> ExchangeRate {
        ExchangeRate(id: id, baseCurrency: CurrencyCode(rawValue: baseCurrency) ?? .CNY, targetCurrency: CurrencyCode(rawValue: targetCurrency) ?? .USD, rate: rate, source: ExchangeRateSource(rawValue: source) ?? .manual, date: date, isManual: isManual, createdAt: createdAt, updatedAt: updatedAt)
    }
}

@Model
final class AppSettingsModel {
    @Attribute(.unique) var id: UUID
    var primaryDisplayCurrency: String
    var defaultReminderConfigData: Data
    var followSystemAppearance: Bool
    var lastBackupAt: Date?
    var dataVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(settings: AppSettings) throws {
        id = settings.id
        primaryDisplayCurrency = settings.primaryDisplayCurrency.rawValue
        defaultReminderConfigData = try JSONEncoder().encode(settings.defaultReminderConfig)
        followSystemAppearance = settings.followSystemAppearance
        lastBackupAt = settings.lastBackupAt
        dataVersion = settings.dataVersion
        createdAt = settings.createdAt
        updatedAt = settings.updatedAt
    }

    func update(from settings: AppSettings) throws {
        primaryDisplayCurrency = settings.primaryDisplayCurrency.rawValue
        defaultReminderConfigData = try JSONEncoder().encode(settings.defaultReminderConfig)
        followSystemAppearance = settings.followSystemAppearance
        lastBackupAt = settings.lastBackupAt
        dataVersion = settings.dataVersion
        createdAt = settings.createdAt
        updatedAt = Date()
    }

    func domain() throws -> AppSettings {
        AppSettings(
            id: id,
            primaryDisplayCurrency: CurrencyCode(rawValue: primaryDisplayCurrency) ?? .CNY,
            defaultReminderConfig: try JSONDecoder().decode(ReminderConfig.self, from: defaultReminderConfigData),
            followSystemAppearance: followSystemAppearance,
            lastBackupAt: lastBackupAt,
            dataVersion: dataVersion,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
