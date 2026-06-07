import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let subscriptions: SubscriptionRepository
    let categories: CategoryRepository
    let templates: ServiceTemplateRepository
    let exchangeRates: ExchangeRateRepository
    let settings: AppSettingsRepository
    let events: AppEventCenter
    let appState: GlobalAppState
    let reminderSync: ReminderSyncService
    let exchangeRateRefresh: ExchangeRateRefreshService
    let backupRestore: BackupRestoreService
    let bootstrapper: AppBootstrapper

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext
        subscriptions = SwiftDataSubscriptionRepository(context: context)
        categories = SwiftDataCategoryRepository(context: context)
        templates = SwiftDataServiceTemplateRepository(context: context)
        exchangeRates = SwiftDataExchangeRateRepository(context: context)
        settings = SwiftDataAppSettingsRepository(context: context)
        events = AppEventCenter()
        appState = GlobalAppState()
        reminderSync = ReminderSyncService(
            subscriptions: subscriptions,
            settings: settings,
            scheduler: UserNotificationScheduler(),
            generator: ReminderPlanGenerator(scheduleResolver: BillingScheduleResolver())
        )
        exchangeRateRefresh = ExchangeRateRefreshService(
            subscriptions: subscriptions,
            settings: settings,
            exchangeRates: exchangeRates,
            provider: FrankfurterExchangeRateProvider()
        )
        backupRestore = BackupRestoreService(
            settings: settings,
            subscriptions: subscriptions,
            categories: categories,
            templates: templates,
            exchangeRates: exchangeRates,
            reminderSync: reminderSync
        )
        bootstrapper = AppBootstrapper(
            settings: settings,
            categories: categories,
            templates: templates,
            reminderSync: reminderSync,
            exchangeRateRefresh: exchangeRateRefresh,
            appState: appState
        )
    }

    static func live() -> AppEnvironment {
        do {
            let schema = Schema([
                SubscriptionRecordModel.self,
                CategoryModel.self,
                ServiceTemplateModel.self,
                ExchangeRateModel.self,
                AppSettingsModel.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return AppEnvironment(modelContainer: container)
        } catch {
            fatalError("Unable to create Subly data store: \(error)")
        }
    }
}

@MainActor
struct AppBootstrapper {
    var settings: AppSettingsRepository
    var categories: CategoryRepository
    var templates: ServiceTemplateRepository
    var reminderSync: ReminderSyncService?
    var exchangeRateRefresh: ExchangeRateRefreshService?
    var appState: GlobalAppState?

    func bootstrap(now: Date = Date()) throws {
        _ = try settings.fetch()
        let existingCategories = try categories.fetchAll(includeArchived: true)
        let existingCategoryIds = Set(existingCategories.map(\.id))
        for category in CategorySeed.systemCategories(now: now) where !existingCategoryIds.contains(category.id) {
            try categories.save(category)
        }

        let allCategories = try categories.fetchAll(includeArchived: true)
        let existingTemplates = try templates.fetchAll()
        let existingTemplateKeys = Set(existingTemplates.map(\.serviceKey))
        let missingTemplates = ServiceTemplateSeed
            .systemTemplates(categories: allCategories, now: now)
            .filter { !existingTemplateKeys.contains($0.serviceKey) }
        if !missingTemplates.isEmpty {
            try templates.saveMany(missingTemplates)
        }
        if let reminderSync {
            Task {
                do {
                    try await reminderSync.rebuildAll(now: now)
                } catch {
                    appState?.showNotice(
                        title: "通知暂未同步",
                        message: "首页可以正常使用，稍后可在设置里重新同步通知。",
                        kind: .warning
                    )
                }
            }
        }
        if let exchangeRateRefresh {
            Task {
                let summary = await exchangeRateRefresh.refreshToday(now: now)
                if summary.hasFailures {
                    appState?.showNotice(
                        title: "汇率暂未完全更新",
                        message: "已保留本地缓存，稍后会继续使用自动汇率更新。",
                        kind: .warning
                    )
                }
            }
        }
    }
}
