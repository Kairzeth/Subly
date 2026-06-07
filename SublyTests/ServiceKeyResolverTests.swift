import XCTest
@testable import Subly

final class ServiceKeyResolverTests: XCTestCase {
    func testTemplateServiceKeyWinsAndHistoryCanBeReused() {
        let category = sampleCategory()
        let template = ServiceTemplate(id: UUID(), serviceName: "ChatGPT", serviceKey: "chatgpt", categoryId: category.id, defaultCurrency: .USD, defaultCycle: .monthly, iconStyle: IconStyle(systemName: "sparkles", colorToken: "ai"), note: nil, websiteURL: nil, isSystem: true, sortOrder: 0, createdAt: date("2026-01-01"), updatedAt: date("2026-01-01"))
        let resolver = ServiceKeyResolver()
        XCTAssertEqual(resolver.resolve(serviceName: "Anything", template: template, history: []), "chatgpt")
        XCTAssertEqual(resolver.resolve(serviceName: "ChatGPT", template: nil, history: [sampleRecord()]), "chatgpt")
    }
}
