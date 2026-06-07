import Foundation

enum AppSettingsChange: Equatable {
    case primaryCurrencyChanged
    case exchangeRateChanged
    case reminderSettingsChanged
    case appearanceChanged
    case dataRestored
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings = AppSettings.defaults()
    @Published var errorMessage: String?
    @Published var lastChange: AppSettingsChange?
    @Published var backupData: Data?
    @Published var restorePreview: RestorePreview?
    @Published var notificationPermissionStatus: NotificationPermissionStatus = .unknown
    @Published var exchangeRates: [ExchangeRate] = []
    @Published var manualRateBase: CurrencyCode = .USD
    @Published var manualRateTarget: CurrencyCode = .CNY
    @Published var manualRateValue = ""
    @Published var manualRateDate = Date()
    @Published var isRefreshingExchangeRates = false
    @Published var exchangeRateRefreshMessage: String?

    private let repository: AppSettingsRepository
    private let exchangeRateRepository: ExchangeRateRepository?
    private let exchangeRateRefresh: ExchangeRateRefreshService?
    private let backupRestore: BackupRestoreService?
    private let reminderSync: ReminderSyncService?
    private let events: AppEventCenter?

    init(
        repository: AppSettingsRepository,
        exchangeRates: ExchangeRateRepository? = nil,
        exchangeRateRefresh: ExchangeRateRefreshService? = nil,
        backupRestore: BackupRestoreService? = nil,
        reminderSync: ReminderSyncService? = nil,
        events: AppEventCenter? = nil
    ) {
        self.repository = repository
        self.exchangeRateRepository = exchangeRates
        self.exchangeRateRefresh = exchangeRateRefresh
        self.backupRestore = backupRestore
        self.reminderSync = reminderSync
        self.events = events
    }

    func load() {
        do {
            settings = try repository.fetch()
            loadExchangeRates()
            refreshNotificationStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPrimaryCurrency(_ currency: CurrencyCode) {
        guard currency.isPrimaryDisplayCurrency else {
            errorMessage = ValidationError.invalidCurrency.localizedDescription
            return
        }
        settings.primaryDisplayCurrency = currency
        save(change: .primaryCurrencyChanged)
    }

    func setFollowSystemAppearance(_ value: Bool) {
        settings.followSystemAppearance = value
        save(change: .appearanceChanged)
    }

    func setDefaultReminder(enabled: Bool, daysBefore: Int) {
        settings.defaultReminderConfig = ReminderConfig(isEnabled: enabled, daysBefore: max(0, daysBefore))
        save(change: .reminderSettingsChanged)
        Task { try? await reminderSync?.rebuildAll() }
    }

    func markBackupSucceeded(at date: Date = Date()) {
        settings.lastBackupAt = date
        save(change: nil)
    }

    func saveManualRate() {
        guard let exchangeRateRepository else {
            errorMessage = "汇率服务未初始化"
            return
        }
        guard manualRateBase != manualRateTarget else {
            errorMessage = "基础币种和目标币种不能相同"
            return
        }
        guard let value = Decimal(string: manualRateValue.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            errorMessage = ValidationError.invalidAmount.localizedDescription
            return
        }
        do {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: manualRateDate)
            let existing = try exchangeRateRepository.fetchRate(base: manualRateBase, target: manualRateTarget, on: day, preferManual: true)
            let now = Date()
            let rate = ExchangeRate(
                id: existing?.isManual == true ? existing!.id : UUID(),
                baseCurrency: manualRateBase,
                targetCurrency: manualRateTarget,
                rate: value,
                source: .manual,
                date: day,
                isManual: true,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try exchangeRateRepository.save(rate)
            manualRateValue = ""
            loadExchangeRates()
            lastChange = .exchangeRateChanged
            events?.post(.statisticsInputsChanged)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAutomaticExchangeRates() {
        guard let exchangeRateRefresh else {
            errorMessage = "自动汇率服务未初始化"
            return
        }
        isRefreshingExchangeRates = true
        exchangeRateRefreshMessage = nil
        Task {
            let summary = await exchangeRateRefresh.refreshToday(force: true)
            isRefreshingExchangeRates = false
            loadExchangeRates()
            lastChange = .exchangeRateChanged
            events?.post(.statisticsInputsChanged)
            if summary.requestedPairs == 0 {
                exchangeRateRefreshMessage = "当前没有需要自动换算的币种"
            } else if summary.hasFailures {
                exchangeRateRefreshMessage = "已更新 \(summary.refreshedPairs) 组，\(summary.failedPairs.count) 组失败"
            } else {
                exchangeRateRefreshMessage = "已更新 \(summary.refreshedPairs) 组今日汇率"
            }
        }
    }

    func prepareBackup() -> Bool {
        guard let backupRestore else {
            errorMessage = "备份服务未初始化"
            return false
        }
        do {
            backupData = try backupRestore.exportBackup()
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func previewRestore(data: Data) -> Bool {
        guard let backupRestore else {
            errorMessage = "恢复服务未初始化"
            return false
        }
        do {
            restorePreview = try backupRestore.preview(data: data)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore(data: Data, mode: RestoreMode = .merge) {
        guard let backupRestore else {
            errorMessage = "恢复服务未初始化"
            return
        }
        do {
            try backupRestore.restore(data: data, mode: mode)
            load()
            lastChange = .dataRestored
            events?.post(.dataRestored)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestNotificationPermission() {
        guard let reminderSync else {
            errorMessage = "通知服务未初始化"
            return
        }
        Task {
            do {
                notificationPermissionStatus = try await reminderSync.requestPermission()
                try? await reminderSync.rebuildAll()
                errorMessage = nil
            } catch {
                notificationPermissionStatus = await reminderSync.permissionStatus()
                errorMessage = SublyError.notificationPermissionDenied.localizedDescription
            }
        }
    }

    func refreshNotificationStatus() {
        guard let reminderSync else { return }
        Task {
            notificationPermissionStatus = await reminderSync.permissionStatus()
        }
    }

    private func loadExchangeRates() {
        exchangeRates = ((try? exchangeRateRepository?.fetchAll()) ?? [])
            .sorted { $0.date > $1.date }
    }

    private func save(change: AppSettingsChange?) {
        do {
            settings.updatedAt = Date()
            try repository.save(settings)
            lastChange = change
            if let change {
                events?.post(.settingsChanged(change))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
