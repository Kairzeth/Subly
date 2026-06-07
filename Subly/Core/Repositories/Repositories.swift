import Foundation
import SwiftData

@MainActor
final class SwiftDataSubscriptionRepository: SubscriptionRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func fetchAll() throws -> [SubscriptionRecord] {
        try context.fetch(FetchDescriptor<SubscriptionRecordModel>(sortBy: [SortDescriptor(\.createdAt)])).map { try $0.domain() }
    }

    func fetch(id: UUID) throws -> SubscriptionRecord? {
        try context.fetch(FetchDescriptor<SubscriptionRecordModel>(predicate: #Predicate { $0.id == id })).first?.domain()
    }

    func fetchActive() throws -> [SubscriptionRecord] {
        try context.fetch(FetchDescriptor<SubscriptionRecordModel>(predicate: #Predicate { $0.statusRawValue == "active" || $0.statusRawValue == "trial" })).map { try $0.domain() }
    }

    func fetchByServiceKey(_ serviceKey: String) throws -> [SubscriptionRecord] {
        try context.fetch(FetchDescriptor<SubscriptionRecordModel>(predicate: #Predicate { $0.serviceKey == serviceKey })).map { try $0.domain() }
    }

    func save(_ record: SubscriptionRecord) throws {
        if let existing = try context.fetch(FetchDescriptor<SubscriptionRecordModel>(predicate: #Predicate { $0.id == record.id })).first {
            try existing.update(from: record)
        } else {
            try context.insert(SubscriptionRecordModel(record: record))
        }
        try context.save()
    }

    func saveMany(_ records: [SubscriptionRecord]) throws {
        for record in records { try save(record) }
    }

    func delete(id: UUID) throws {
        if let existing = try context.fetch(FetchDescriptor<SubscriptionRecordModel>(predicate: #Predicate { $0.id == id })).first {
            context.delete(existing)
            try context.save()
        }
    }

    func replaceAll(_ records: [SubscriptionRecord]) throws {
        for model in try context.fetch(FetchDescriptor<SubscriptionRecordModel>()) {
            context.delete(model)
        }
        for record in records {
            try context.insert(SubscriptionRecordModel(record: record))
        }
        try context.save()
    }
}

@MainActor
final class SwiftDataCategoryRepository: CategoryRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func fetchAll(includeArchived: Bool) throws -> [Category] {
        let models: [CategoryModel]
        if includeArchived {
            models = try context.fetch(FetchDescriptor<CategoryModel>(sortBy: [SortDescriptor(\.sortOrder)]))
        } else {
            models = try context.fetch(FetchDescriptor<CategoryModel>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortOrder)]))
        }
        return models.map { $0.domain() }
    }

    func fetch(id: UUID) throws -> Category? {
        try context.fetch(FetchDescriptor<CategoryModel>(predicate: #Predicate { $0.id == id })).first?.domain()
    }

    func save(_ category: Category) throws {
        if let existing = try context.fetch(FetchDescriptor<CategoryModel>(predicate: #Predicate { $0.id == category.id })).first {
            existing.update(from: category)
        } else {
            context.insert(CategoryModel(category: category))
        }
        try context.save()
    }

    func saveMany(_ categories: [Category]) throws {
        for category in categories { try save(category) }
    }

    func archive(id: UUID) throws {
        guard let existing = try context.fetch(FetchDescriptor<CategoryModel>(predicate: #Predicate { $0.id == id })).first else { return }
        existing.isArchived = true
        existing.updatedAt = Date()
        try context.save()
    }

    func replaceAll(_ categories: [Category]) throws {
        for model in try context.fetch(FetchDescriptor<CategoryModel>()) {
            context.delete(model)
        }
        for category in categories {
            context.insert(CategoryModel(category: category))
        }
        try context.save()
    }
}

@MainActor
final class SwiftDataServiceTemplateRepository: ServiceTemplateRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func fetchAll() throws -> [ServiceTemplate] {
        try context.fetch(FetchDescriptor<ServiceTemplateModel>(sortBy: [SortDescriptor(\.sortOrder)])).map { try $0.domain() }
    }

    func fetch(serviceKey: String) throws -> ServiceTemplate? {
        try context.fetch(FetchDescriptor<ServiceTemplateModel>(predicate: #Predicate { $0.serviceKey == serviceKey })).first?.domain()
    }

    func save(_ template: ServiceTemplate) throws {
        if let existing = try context.fetch(FetchDescriptor<ServiceTemplateModel>(predicate: #Predicate { $0.id == template.id })).first {
            try existing.update(from: template)
        } else {
            try context.insert(ServiceTemplateModel(template: template))
        }
        try context.save()
    }

    func saveMany(_ templates: [ServiceTemplate]) throws {
        for template in templates {
            if try fetch(serviceKey: template.serviceKey) == nil {
                try save(template)
            }
        }
    }

    func replaceAll(_ templates: [ServiceTemplate]) throws {
        for model in try context.fetch(FetchDescriptor<ServiceTemplateModel>()) {
            context.delete(model)
        }
        for template in templates {
            try context.insert(ServiceTemplateModel(template: template))
        }
        try context.save()
    }
}

@MainActor
final class SwiftDataExchangeRateRepository: ExchangeRateRepository {
    private let context: ModelContext
    private let calendar = Calendar(identifier: .gregorian)
    init(context: ModelContext) { self.context = context }

    func fetchAll() throws -> [ExchangeRate] {
        try context.fetch(FetchDescriptor<ExchangeRateModel>(sortBy: [SortDescriptor(\.date, order: .reverse)])).map { $0.domain() }
    }

    func fetchRate(base: CurrencyCode, target: CurrencyCode, on date: Date, preferManual: Bool) throws -> ExchangeRate? {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let rates = try context.fetch(FetchDescriptor<ExchangeRateModel>(predicate: #Predicate {
            $0.baseCurrency == base.rawValue && $0.targetCurrency == target.rawValue && $0.date >= day && $0.date < next
        })).map { $0.domain() }
        return sorted(rates, preferManual: preferManual).first
    }

    func fetchLatestRate(base: CurrencyCode, target: CurrencyCode, upTo date: Date, preferManual: Bool) throws -> ExchangeRate? {
        let day = calendar.startOfDay(for: date)
        let rates = try context.fetch(FetchDescriptor<ExchangeRateModel>(predicate: #Predicate {
            $0.baseCurrency == base.rawValue && $0.targetCurrency == target.rawValue && $0.date <= day
        })).map { $0.domain() }
        return sorted(rates, preferManual: preferManual).first
    }

    func save(_ rate: ExchangeRate) throws {
        if let existing = try context.fetch(FetchDescriptor<ExchangeRateModel>(predicate: #Predicate { $0.id == rate.id })).first {
            existing.update(from: rate)
        } else {
            context.insert(ExchangeRateModel(rate: rate))
        }
        try context.save()
    }

    func saveMany(_ rates: [ExchangeRate]) throws {
        for rate in rates { try save(rate) }
    }

    func replaceAll(_ rates: [ExchangeRate]) throws {
        for model in try context.fetch(FetchDescriptor<ExchangeRateModel>()) {
            context.delete(model)
        }
        for rate in rates {
            context.insert(ExchangeRateModel(rate: rate))
        }
        try context.save()
    }

    private func sorted(_ rates: [ExchangeRate], preferManual: Bool) -> [ExchangeRate] {
        rates.sorted {
            if preferManual, $0.isManual != $1.isManual { return $0.isManual && !$1.isManual }
            return $0.date > $1.date
        }
    }
}

@MainActor
final class SwiftDataAppSettingsRepository: AppSettingsRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func fetch() throws -> AppSettings {
        if let model = try context.fetch(FetchDescriptor<AppSettingsModel>()).first {
            return try model.domain()
        }
        let defaults = AppSettings.defaults()
        try save(defaults)
        return defaults
    }

    func save(_ settings: AppSettings) throws {
        if let existing = try context.fetch(FetchDescriptor<AppSettingsModel>(predicate: #Predicate { $0.id == settings.id })).first {
            try existing.update(from: settings)
        } else {
            try context.insert(AppSettingsModel(settings: settings))
        }
        try context.save()
    }
}
