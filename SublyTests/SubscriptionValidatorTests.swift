import XCTest
@testable import Subly

final class SubscriptionValidatorTests: XCTestCase {
    func testValidatorRejectsEmptyNameAndMissingPaidCurrency() {
        let category = sampleCategory()
        var draft = SubscriptionDraft(serviceName: " ", serviceKey: nil, categoryId: category.id, listedAmount: 1, listedCurrency: .CNY, paidAmount: nil, paidCurrency: nil, billingCycle: .monthly, startDate: date("2026-01-01"), endDate: nil, nextBillingDate: nil, isNextBillingDateManual: false, status: .active, paymentMethod: nil, reminderConfig: nil, websiteURL: nil, note: nil)
        XCTAssertThrowsError(try SubscriptionValidator().validate(draft, categories: [category]))
        draft.serviceName = "Test"
        draft.paidAmount = 1
        XCTAssertThrowsError(try SubscriptionValidator().validate(draft, categories: [category]))
    }

    func testValidatorRequiresEndDateForOneTimePurchase() {
        let category = sampleCategory()
        let draft = SubscriptionDraft(serviceName: "Setapp Deal", serviceKey: nil, categoryId: category.id, listedAmount: 100, listedCurrency: .CNY, paidAmount: nil, paidCurrency: nil, billingCycle: .oneTime, startDate: date("2026-01-01"), endDate: nil, nextBillingDate: nil, isNextBillingDateManual: false, status: .oneTime, paymentMethod: nil, reminderConfig: nil, websiteURL: nil, note: nil)

        XCTAssertThrowsError(try SubscriptionValidator().validate(draft, categories: [category]))
    }
}
