import Foundation

struct CategoryEditorState: Equatable {
    var name = ""
    var iconName = "square.grid.2x2"
    var colorToken = "custom"
}

struct CategoryManagementRowState: Identifiable, Equatable {
    var id: UUID
    var name: String
    var iconName: String
    var colorToken: String
    var sortOrder: Int
    var isSystem: Bool
    var isArchived: Bool
    var usageCount: Int
}

@MainActor
struct CategoryCommandService {
    var categories: CategoryRepository
    var subscriptions: SubscriptionRepository

    func create(name: String, iconName: String, colorToken: String, now: Date = Date()) throws -> Category {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ValidationError.emptyName }
        let existing = try categories.fetchAll(includeArchived: true)
        let nextSortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let category = Category(
            id: UUID(),
            name: trimmedName,
            iconName: iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "square.grid.2x2" : iconName,
            colorToken: colorToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "custom" : colorToken,
            sortOrder: nextSortOrder,
            isSystem: false,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        try categories.save(category)
        return category
    }

    func update(id: UUID, name: String, iconName: String, colorToken: String, now: Date = Date()) throws -> Category {
        guard var category = try categories.fetch(id: id) else {
            throw SublyError.persistence("Category not found")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ValidationError.emptyName }
        category.name = trimmedName
        category.iconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.iconName : iconName
        category.colorToken = colorToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.colorToken : colorToken
        category.updatedAt = now
        try categories.save(category)
        return category
    }

    func updateSortOrder(ids: [UUID], now: Date = Date()) throws {
        for (index, id) in ids.enumerated() {
            guard var category = try categories.fetch(id: id) else { continue }
            category.sortOrder = index
            category.updatedAt = now
            try categories.save(category)
        }
    }

    func archive(id: UUID) throws {
        try categories.archive(id: id)
    }

    func usageCount(for categoryId: UUID) throws -> Int {
        try subscriptions.fetchAll().filter { $0.categoryId == categoryId }.count
    }
}

@MainActor
final class CategoryManagementViewModel: ObservableObject {
    @Published var rows: [CategoryManagementRowState] = []
    @Published var editor = CategoryEditorState()
    @Published var editingCategoryId: UUID?
    @Published var errorMessage: String?

    private let queryRepository: CategoryRepository
    private let commandService: CategoryCommandService
    private let events: AppEventCenter?

    init(categories: CategoryRepository, subscriptions: SubscriptionRepository, events: AppEventCenter? = nil) {
        self.queryRepository = categories
        self.commandService = CategoryCommandService(categories: categories, subscriptions: subscriptions)
        self.events = events
    }

    func load() {
        do {
            rows = try queryRepository.fetchAll(includeArchived: true)
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { category in
                    CategoryManagementRowState(
                        id: category.id,
                        name: category.name,
                        iconName: category.iconName,
                        colorToken: category.colorToken,
                        sortOrder: category.sortOrder,
                        isSystem: category.isSystem,
                        isArchived: category.isArchived,
                        usageCount: try commandService.usageCount(for: category.id)
                    )
                }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditing(_ row: CategoryManagementRowState) {
        editingCategoryId = row.id
        editor = CategoryEditorState(name: row.name, iconName: row.iconName, colorToken: row.colorToken)
    }

    func resetEditor() {
        editingCategoryId = nil
        editor = CategoryEditorState()
    }

    func saveEditor() {
        do {
            if let editingCategoryId {
                _ = try commandService.update(
                    id: editingCategoryId,
                    name: editor.name,
                    iconName: editor.iconName,
                    colorToken: editor.colorToken
                )
            } else {
                _ = try commandService.create(
                    name: editor.name,
                    iconName: editor.iconName,
                    colorToken: editor.colorToken
                )
            }
            resetEditor()
            load()
            events?.post(.statisticsInputsChanged)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        rows.move(fromOffsets: source, toOffset: destination)
        do {
            try commandService.updateSortOrder(ids: rows.map(\.id))
            load()
            events?.post(.statisticsInputsChanged)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archive(id: UUID) {
        do {
            try commandService.archive(id: id)
            load()
            events?.post(.statisticsInputsChanged)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
