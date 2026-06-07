import Foundation

struct SubscriptionDraft {
    var serviceName: String
    var serviceKey: String?
    var categoryId: UUID
    var listedAmount: Decimal
    var listedCurrency: CurrencyCode
    var paidAmount: Decimal?
    var paidCurrency: CurrencyCode?
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
}

@MainActor
struct SubscriptionQueryService {
    var repository: SubscriptionRepository

    func all(status: SubscriptionStatus? = nil) throws -> [SubscriptionRecord] {
        let records = try repository.fetchAll()
        guard let status else { return records }
        return records.filter { $0.status == status }
    }

    func detail(id: UUID) throws -> SubscriptionRecord? {
        try repository.fetch(id: id)
    }
}

struct SubscriptionValidator {
    func validate(_ draft: SubscriptionDraft, categories: [Category], allowArchivedCategory: Bool = false) throws {
        guard !draft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.emptyName }
        guard draft.listedAmount >= 0 else { throw ValidationError.invalidAmount }
        if let paidAmount = draft.paidAmount, paidAmount < 0 { throw ValidationError.invalidAmount }
        if draft.paidAmount != nil, draft.paidCurrency == nil { throw ValidationError.missingPaidCurrency }
        try draft.billingCycle.validate()
        if let endDate = draft.endDate, Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: draft.startDate) {
            throw ValidationError.invalidDateRange
        }
        if let nextBillingDate = draft.nextBillingDate, Calendar.current.startOfDay(for: nextBillingDate) < Calendar.current.startOfDay(for: draft.startDate) {
            throw ValidationError.invalidDateRange
        }
        if let websiteURL = draft.websiteURL, websiteURL.scheme == nil {
            throw ValidationError.invalidURL
        }
        guard categories.contains(where: { $0.id == draft.categoryId && (!$0.isArchived || allowArchivedCategory) }) else { throw ValidationError.missingCategory }
    }
}

struct ServiceKeyResolver {
    func resolve(serviceName: String, template: ServiceTemplate?, history: [SubscriptionRecord], restoringFrom record: SubscriptionRecord? = nil) -> String {
        if let template { return template.serviceKey }
        if let record { return record.serviceKey }
        let normalized = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = history.first(where: { $0.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            return existing.serviceKey
        }
        return "local-\(normalized.replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString.prefix(8))"
    }
}

@MainActor
final class SubscriptionFormViewModel: ObservableObject {
    @Published var serviceName = ""
    @Published var listedAmount = ""
    @Published var listedCurrency: CurrencyCode = .CNY
    @Published var paidAmount = ""
    @Published var paidCurrency: CurrencyCode = .CNY
    @Published var hasPaidAmount = false
    @Published var billingCycle: BillingCycle = .monthly
    @Published var customCycleDays = 30
    @Published var startDate = Date()
    @Published var hasEndDate = false
    @Published var endDate = Date()
    @Published var hasManualNextBillingDate = false
    @Published var nextBillingDate = Date()
    @Published var status: SubscriptionStatus = .active
    @Published var paymentMethod = ""
    @Published var note = ""
    @Published var websiteURL = ""
    @Published var reminderEnabled = true
    @Published var reminderDaysBefore = 1
    @Published var categories: [Category] = []
    @Published var templates: [ServiceTemplate] = []
    @Published var selectedTemplateKey: String?
    @Published var selectedCategoryId: UUID?
    @Published var errorMessage: String?

    let commandService: SubscriptionCommandService
    private let categoryRepository: CategoryRepository
    private let templateRepository: ServiceTemplateRepository?
    private let existingRecord: SubscriptionRecord?

    var isEditing: Bool {
        existingRecord != nil
    }

    var selectedTemplateName: String {
        selectedTemplate?.serviceName ?? "手动创建"
    }

    init(
        commandService: SubscriptionCommandService,
        categoryRepository: CategoryRepository,
        templateRepository: ServiceTemplateRepository? = nil,
        existingRecord: SubscriptionRecord? = nil
    ) {
        self.commandService = commandService
        self.categoryRepository = categoryRepository
        self.templateRepository = templateRepository
        self.existingRecord = existingRecord
    }

    func load() {
        do {
            categories = try categoryRepository.fetchAll(includeArchived: isEditing)
            templates = isEditing ? [] : ((try? templateRepository?.fetchAll()) ?? [])
            selectedCategoryId = selectedCategoryId ?? categories.first?.id
            if let existingRecord, serviceName.isEmpty {
                apply(existingRecord)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectTemplate(serviceKey: String?) {
        selectedTemplateKey = serviceKey
        guard let serviceKey, let template = templates.first(where: { $0.serviceKey == serviceKey }) else { return }
        serviceName = template.serviceName
        selectedCategoryId = template.categoryId
        listedCurrency = template.defaultCurrency
        billingCycle = template.defaultCycle
        if case .customDays(let days) = template.defaultCycle {
            customCycleDays = days
        }
        websiteURL = template.websiteURL?.absoluteString ?? ""
    }

    func save() throws -> SubscriptionRecord {
        guard let categoryId = selectedCategoryId else { throw ValidationError.missingCategory }
        let amount = Decimal(string: listedAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        let paid = hasPaidAmount ? Decimal(string: paidAmount.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        let url = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: websiteURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let cycle: BillingCycle = switch billingCycle {
        case .customDays:
            .customDays(customCycleDays)
        default:
            billingCycle
        }
        let draft = SubscriptionDraft(
            serviceName: serviceName,
            serviceKey: selectedTemplate?.serviceKey,
            categoryId: categoryId,
            listedAmount: amount,
            listedCurrency: listedCurrency,
            paidAmount: paid,
            paidCurrency: paid == nil ? nil : paidCurrency,
            billingCycle: cycle,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            nextBillingDate: hasManualNextBillingDate ? nextBillingDate : nil,
            isNextBillingDateManual: hasManualNextBillingDate,
            status: status,
            paymentMethod: paymentMethod.trimmedNilIfEmpty,
            reminderConfig: ReminderConfig(isEnabled: reminderEnabled, daysBefore: reminderDaysBefore),
            websiteURL: url,
            note: note.trimmedNilIfEmpty
        )
        do {
            if let existingRecord {
                return try commandService.update(id: existingRecord.id, from: draft)
            }
            return try commandService.create(from: draft)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private var selectedTemplate: ServiceTemplate? {
        guard let selectedTemplateKey else { return nil }
        return templates.first { $0.serviceKey == selectedTemplateKey }
    }

    private func apply(_ record: SubscriptionRecord) {
        serviceName = record.serviceName
        listedAmount = "\(record.listedAmount)"
        listedCurrency = record.listedCurrency
        if let paidAmount = record.paidAmount {
            hasPaidAmount = true
            self.paidAmount = "\(paidAmount)"
        }
        paidCurrency = record.paidCurrency ?? record.listedCurrency
        billingCycle = record.billingCycle
        if case .customDays(let days) = record.billingCycle {
            customCycleDays = days
        }
        startDate = record.startDate
        hasEndDate = record.endDate != nil
        endDate = record.endDate ?? record.startDate
        hasManualNextBillingDate = record.isNextBillingDateManual
        nextBillingDate = record.nextBillingDate ?? record.startDate
        status = record.status
        paymentMethod = record.paymentMethod ?? ""
        note = record.note ?? ""
        websiteURL = record.websiteURL?.absoluteString ?? ""
        reminderEnabled = record.reminderConfig?.isEnabled ?? true
        reminderDaysBefore = record.reminderConfig?.daysBefore ?? 1
        selectedCategoryId = record.categoryId
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

@MainActor
struct SubscriptionCommandService {
    var repository: SubscriptionRepository
    var categories: CategoryRepository
    var reminderSync: ReminderSyncService?
    var events: AppEventCenter?
    var validator = SubscriptionValidator()
    var serviceKeyResolver = ServiceKeyResolver()

    func create(from draft: SubscriptionDraft, template: ServiceTemplate? = nil, now: Date = Date()) throws -> SubscriptionRecord {
        let allCategories = try categories.fetchAll(includeArchived: false)
        try validator.validate(draft, categories: allCategories)
        let history = try repository.fetchAll()
        let key = draft.serviceKey ?? serviceKeyResolver.resolve(serviceName: draft.serviceName, template: template, history: history)
        let record = SubscriptionRecord(
            id: UUID(),
            serviceName: draft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines),
            serviceKey: key,
            categoryId: draft.categoryId,
            listedAmount: draft.listedAmount,
            listedCurrency: draft.listedCurrency,
            paidAmount: draft.paidAmount,
            paidCurrency: draft.paidCurrency,
            displayCurrency: .CNY,
            billingCycle: draft.billingCycle,
            startDate: draft.startDate,
            endDate: draft.endDate,
            nextBillingDate: draft.nextBillingDate,
            isNextBillingDateManual: draft.isNextBillingDateManual,
            status: draft.status,
            paymentMethod: draft.paymentMethod,
            reminderConfig: draft.reminderConfig,
            websiteURL: draft.websiteURL,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        )
        try repository.save(record)
        Task { try? await reminderSync?.sync(record: record) }
        events?.post(.subscriptionsChanged)
        return record
    }

    func update(id: UUID, from draft: SubscriptionDraft, now: Date = Date()) throws -> SubscriptionRecord {
        guard let old = try repository.fetch(id: id) else { throw SublyError.persistence("Subscription not found") }
        let allCategories = try categories.fetchAll(includeArchived: true)
        try validator.validate(draft, categories: allCategories, allowArchivedCategory: true)
        let record = SubscriptionRecord(
            id: old.id,
            serviceName: draft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines),
            serviceKey: old.serviceKey,
            categoryId: draft.categoryId,
            listedAmount: draft.listedAmount,
            listedCurrency: draft.listedCurrency,
            paidAmount: draft.paidAmount,
            paidCurrency: draft.paidCurrency,
            displayCurrency: old.displayCurrency,
            billingCycle: draft.billingCycle,
            startDate: draft.startDate,
            endDate: draft.endDate,
            nextBillingDate: draft.nextBillingDate,
            isNextBillingDateManual: draft.isNextBillingDateManual,
            status: draft.status,
            paymentMethod: draft.paymentMethod,
            reminderConfig: draft.reminderConfig,
            websiteURL: draft.websiteURL,
            note: draft.note,
            createdAt: old.createdAt,
            updatedAt: now
        )
        try repository.save(record)
        if record.status.allowsFutureBillingReminder {
            Task { try? await reminderSync?.sync(record: record) }
        } else {
            Task { await reminderSync?.cancel(recordId: id) }
        }
        events?.post(.subscriptionsChanged)
        return record
    }

    func pause(id: UUID, on date: Date) throws {
        guard var record = try repository.fetch(id: id) else { return }
        guard record.status != .cancelled && record.status != .expired else {
            throw SublyError.invalidOperation("已取消或已过期的订阅不能暂停")
        }
        record.status = .paused
        record.endDate = date
        record.updatedAt = Date()
        try repository.save(record)
        Task { await reminderSync?.cancel(recordId: id) }
        events?.post(.subscriptionsChanged)
    }

    func cancel(id: UUID, on date: Date) throws {
        guard var record = try repository.fetch(id: id) else { return }
        record.status = .cancelled
        record.endDate = date
        record.updatedAt = Date()
        try repository.save(record)
        Task { await reminderSync?.cancel(recordId: id) }
        events?.post(.subscriptionsChanged)
    }

    func delete(id: UUID) throws {
        try repository.delete(id: id)
        Task { await reminderSync?.cancel(recordId: id) }
        events?.post(.subscriptionsChanged)
    }

    func restore(from id: UUID, startDate: Date, amount: Decimal, now: Date = Date()) throws -> SubscriptionRecord? {
        guard let old = try repository.fetch(id: id) else { return nil }
        let draft = SubscriptionDraft(
            serviceName: old.serviceName,
            serviceKey: old.serviceKey,
            categoryId: old.categoryId,
            listedAmount: amount,
            listedCurrency: old.listedCurrency,
            paidAmount: nil,
            paidCurrency: nil,
            billingCycle: old.billingCycle,
            startDate: startDate,
            endDate: nil,
            nextBillingDate: nil,
            isNextBillingDateManual: false,
            status: .active,
            paymentMethod: old.paymentMethod,
            reminderConfig: old.reminderConfig,
            websiteURL: old.websiteURL,
            note: old.note
        )
        return try create(from: draft, now: now)
    }
}

struct SubscriptionDetailState: Equatable {
    var record: SubscriptionRecord
}

@MainActor
final class SubscriptionDetailViewModel: ObservableObject {
    @Published var state: SubscriptionDetailState?
    @Published var actionDate = Date()
    @Published var restoreAmount = ""
    @Published var errorMessage: String?

    private let id: UUID
    private let queryService: SubscriptionQueryService
    let commandService: SubscriptionCommandService

    init(id: UUID, queryService: SubscriptionQueryService, commandService: SubscriptionCommandService) {
        self.id = id
        self.queryService = queryService
        self.commandService = commandService
    }

    func load() {
        do {
            if let record = try queryService.detail(id: id) {
                state = SubscriptionDetailState(record: record)
                actionDate = record.endDate ?? Date()
                restoreAmount = "\(record.listedAmount)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        perform {
            try commandService.pause(id: id, on: actionDate)
        }
    }

    func cancel() {
        perform {
            try commandService.cancel(id: id, on: actionDate)
        }
    }

    func delete() {
        perform {
            try commandService.delete(id: id)
        }
    }

    func restore() {
        perform {
            let amount = Decimal(string: restoreAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            _ = try commandService.restore(from: id, startDate: Date(), amount: amount)
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
