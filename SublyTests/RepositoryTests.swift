import SwiftData
import XCTest
@testable import Subly

@MainActor
final class RepositoryTests: XCTestCase {
    func testSubscriptionRepositorySavesFetchesActiveAndDeletes() throws {
        let container = try makeInMemoryContainer()
        let repository = SwiftDataSubscriptionRepository(context: container.mainContext)
        let active = sampleRecord(status: .active)
        let pending = sampleRecord(name: "Claude", serviceKey: "claude", status: .pendingRenewalDecision)
        let cancelled = sampleRecord(name: "Netflix", serviceKey: "netflix", status: .cancelled)
        try repository.saveMany([active, pending, cancelled])

        XCTAssertEqual(try repository.fetchAll().count, 3)
        XCTAssertEqual(Set(try repository.fetchActive().map(\.id)), Set([active.id, pending.id]))
        XCTAssertEqual(try repository.fetchByServiceKey("netflix").first?.id, cancelled.id)

        try repository.delete(id: active.id)
        XCTAssertNil(try repository.fetch(id: active.id))
    }

    func testCategoryArchiveHidesFromDefaultFetch() throws {
        let container = try makeInMemoryContainer()
        let repository = SwiftDataCategoryRepository(context: container.mainContext)
        let category = sampleCategory()
        try repository.save(category)
        try repository.archive(id: category.id)

        XCTAssertTrue(try repository.fetchAll(includeArchived: false).isEmpty)
        XCTAssertEqual(try repository.fetchAll(includeArchived: true).count, 1)
    }

    func testTemplateSeedDoesNotDuplicateServiceKeys() throws {
        let container = try makeInMemoryContainer()
        let categoryRepository = SwiftDataCategoryRepository(context: container.mainContext)
        let templateRepository = SwiftDataServiceTemplateRepository(context: container.mainContext)
        for category in CategorySeed.systemCategories(now: date("2026-01-01")) {
            try categoryRepository.save(category)
        }
        let categories = try categoryRepository.fetchAll(includeArchived: true)
        let templates = ServiceTemplateSeed.systemTemplates(categories: categories, now: date("2026-01-01"))
        try templateRepository.saveMany(templates)
        try templateRepository.saveMany(templates)

        XCTAssertEqual(try templateRepository.fetchAll().count, 16)
        XCTAssertEqual(try templateRepository.fetch(serviceKey: "chatgpt")?.serviceName, "ChatGPT")
    }

    func testExchangeRateLatestDoesNotReadFutureRatesAndCanPreferManual() throws {
        let container = try makeInMemoryContainer()
        let repository = SwiftDataExchangeRateRepository(context: container.mainContext)
        try repository.save(sampleRate(rate: 7, date: date("2026-01-01"), manual: false))
        try repository.save(sampleRate(rate: 8, date: date("2026-01-01"), manual: true))
        try repository.save(sampleRate(rate: 9, date: date("2026-02-01"), manual: false))

        XCTAssertEqual(try repository.fetchLatestRate(base: .USD, target: .CNY, upTo: date("2026-01-15"), preferManual: true)?.rate, 8)
    }

    func testSettingsRepositoryCreatesSingleton() throws {
        let container = try makeInMemoryContainer()
        let repository = SwiftDataAppSettingsRepository(context: container.mainContext)
        var settings = try repository.fetch()
        XCTAssertEqual(settings.primaryDisplayCurrency, .CNY)
        settings.primaryDisplayCurrency = .USD
        try repository.save(settings)
        XCTAssertEqual(try repository.fetch().primaryDisplayCurrency, .USD)
    }
}
