import XCTest
@testable import Subly

@MainActor
final class AppBootstrapperTests: XCTestCase {
    func testBootstrapFillsMissingSystemCategoryWithoutOverwritingExistingSortOrder() throws {
        let container = try makeInMemoryContainer()
        let categories = SwiftDataCategoryRepository(context: container.mainContext)
        let templates = SwiftDataServiceTemplateRepository(context: container.mainContext)
        let settings = SwiftDataAppSettingsRepository(context: container.mainContext)
        let bootstrapper = AppBootstrapper(settings: settings, categories: categories, templates: templates)

        var existingAI = CategorySeed.systemCategories(now: date("2026-01-01")).first { $0.name == "AI" }!
        existingAI.sortOrder = 99
        try categories.save(existingAI)

        try bootstrapper.bootstrap(now: date("2026-01-02"))

        let seededCategories = try categories.fetchAll(includeArchived: true)
        XCTAssertEqual(seededCategories.count, 10)
        XCTAssertEqual(seededCategories.first { $0.name == "AI" }?.sortOrder, 99)
    }

    func testBootstrapFillsMissingSystemTemplateByServiceKey() throws {
        let container = try makeInMemoryContainer()
        let categories = SwiftDataCategoryRepository(context: container.mainContext)
        let templates = SwiftDataServiceTemplateRepository(context: container.mainContext)
        let settings = SwiftDataAppSettingsRepository(context: container.mainContext)
        let bootstrapper = AppBootstrapper(settings: settings, categories: categories, templates: templates)

        let seededCategories = CategorySeed.systemCategories(now: date("2026-01-01"))
        try seededCategories.forEach { try categories.save($0) }
        let allTemplates = ServiceTemplateSeed.systemTemplates(categories: seededCategories, now: date("2026-01-01"))
        try templates.save(allTemplates.first!)

        try bootstrapper.bootstrap(now: date("2026-01-02"))

        XCTAssertEqual(try templates.fetchAll().count, 16)
    }
}
