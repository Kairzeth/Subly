import Foundation
import SwiftData
import XCTest
@testable import Subly

@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema([
        SubscriptionRecordModel.self,
        CategoryModel.self,
        ServiceTemplateModel.self,
        ExchangeRateModel.self,
        AppSettingsModel.self
    ])
    return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
}

func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

func date(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = fixedCalendar()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: text)!
}

func sampleCategory(now: Date = date("2026-01-01")) -> Subly.Category {
    Subly.Category(id: UUID(), name: "AI", iconName: "sparkles", colorToken: "ai", sortOrder: 0, isSystem: true, isArchived: false, createdAt: now, updatedAt: now)
}

func sampleRecord(
    name: String = "ChatGPT",
    serviceKey: String = "chatgpt",
    categoryId: UUID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
    amount: Decimal = 20,
    currency: CurrencyCode = .USD,
    cycle: BillingCycle = .monthly,
    start: Date = date("2026-01-01"),
    end: Date? = nil,
    status: SubscriptionStatus = .active
) -> SubscriptionRecord {
    SubscriptionRecord(
        id: UUID(),
        serviceName: name,
        serviceKey: serviceKey,
        categoryId: categoryId,
        listedAmount: amount,
        listedCurrency: currency,
        paidAmount: nil,
        paidCurrency: nil,
        displayCurrency: .CNY,
        billingCycle: cycle,
        startDate: start,
        endDate: end,
        nextBillingDate: nil,
        isNextBillingDateManual: false,
        status: status,
        paymentMethod: nil,
        reminderConfig: nil,
        websiteURL: nil,
        note: nil,
        createdAt: start,
        updatedAt: start
    )
}

func sampleRate(base: CurrencyCode = .USD, target: CurrencyCode = .CNY, rate: Decimal = 7, date rateDate: Date = date("2026-01-01"), manual: Bool = false) -> ExchangeRate {
    ExchangeRate(id: UUID(), baseCurrency: base, targetCurrency: target, rate: rate, source: manual ? .manual : .mock, date: rateDate, isManual: manual, createdAt: rateDate, updatedAt: rateDate)
}
