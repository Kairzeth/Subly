import Foundation

@MainActor
protocol SubscriptionRepository {
    func fetchAll() throws -> [SubscriptionRecord]
    func fetch(id: UUID) throws -> SubscriptionRecord?
    func fetchActive() throws -> [SubscriptionRecord]
    func fetchByServiceKey(_ serviceKey: String) throws -> [SubscriptionRecord]
    func save(_ record: SubscriptionRecord) throws
    func saveMany(_ records: [SubscriptionRecord]) throws
    func delete(id: UUID) throws
    func replaceAll(_ records: [SubscriptionRecord]) throws
}

@MainActor
protocol CategoryRepository {
    func fetchAll(includeArchived: Bool) throws -> [Category]
    func fetch(id: UUID) throws -> Category?
    func save(_ category: Category) throws
    func saveMany(_ categories: [Category]) throws
    func archive(id: UUID) throws
    func replaceAll(_ categories: [Category]) throws
}

@MainActor
protocol ServiceTemplateRepository {
    func fetchAll() throws -> [ServiceTemplate]
    func fetch(serviceKey: String) throws -> ServiceTemplate?
    func save(_ template: ServiceTemplate) throws
    func saveMany(_ templates: [ServiceTemplate]) throws
    func replaceAll(_ templates: [ServiceTemplate]) throws
}

@MainActor
protocol ExchangeRateRepository {
    func fetchAll() throws -> [ExchangeRate]
    func fetchRate(base: CurrencyCode, target: CurrencyCode, on date: Date, preferManual: Bool) throws -> ExchangeRate?
    func fetchLatestRate(base: CurrencyCode, target: CurrencyCode, upTo date: Date, preferManual: Bool) throws -> ExchangeRate?
    func save(_ rate: ExchangeRate) throws
    func saveMany(_ rates: [ExchangeRate]) throws
    func replaceAll(_ rates: [ExchangeRate]) throws
}

@MainActor
protocol AppSettingsRepository {
    func fetch() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}
