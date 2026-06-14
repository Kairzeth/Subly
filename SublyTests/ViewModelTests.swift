import XCTest
@testable import Subly

@MainActor
final class ViewModelTests: XCTestCase {
    func testHomeViewModelMapsActiveSubscriptions() {
        let category = sampleCategory()
        let repository = InMemorySubscriptionRepository(records: [
            sampleRecord(categoryId: category.id, currency: .CNY),
            sampleRecord(name: "Pending", serviceKey: "pending", categoryId: category.id, currency: .CNY, status: .pendingRenewalDecision),
            sampleRecord(name: "Paused", serviceKey: "paused", categoryId: category.id, currency: .CNY, status: .paused)
        ])
        let viewModel = HomeViewModel(
            subscriptions: repository,
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar()
        )
        viewModel.load()
        XCTAssertEqual(viewModel.state.activeCount, 2)
        XCTAssertEqual(Set(viewModel.state.subscriptionRows.map(\.name)), Set(["ChatGPT", "Pending"]))
    }

    func testHomeRowsUseSemanticDisplayDates() {
        let category = sampleCategory()
        let record = sampleRecord(categoryId: category.id, currency: .CNY, start: date("2026-01-01"))
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [record]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar(),
            now: { date("2026-01-15") }
        )

        viewModel.load()

        XCTAssertEqual(viewModel.state.subscriptionRows.first?.displayDate, date("2026-02-01"))
        XCTAssertEqual(viewModel.state.subscriptionRows.first?.displayDateLabel, "下次扣费")
    }

    func testHomeRowsPreferEndDateWhenItMatchesNextBillingDate() {
        let category = sampleCategory()
        let record = sampleRecord(
            name: "VPN",
            serviceKey: "vpn",
            categoryId: category.id,
            amount: 108,
            currency: .CNY,
            cycle: .quarterly,
            start: date("2025-10-02"),
            end: date("2026-07-02")
        )
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [record]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar(),
            now: { date("2026-06-14") }
        )

        viewModel.load()

        XCTAssertEqual(viewModel.state.subscriptionRows.first?.displayDate, date("2026-07-02"))
        XCTAssertEqual(viewModel.state.subscriptionRows.first?.displayDateLabel, "结束")
        XCTAssertEqual(viewModel.state.dueSoonRows.first?.subtitle, "订阅到期")
    }

    func testHomeDueSoonUsesEarlierOfEndDateAndBillingDate() {
        let category = sampleCategory()
        let record = sampleRecord(
            categoryId: category.id,
            currency: .CNY,
            cycle: .yearly,
            start: date("2026-01-01"),
            end: date("2026-06-20")
        )
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [record]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar(),
            now: { date("2026-06-01") }
        )

        viewModel.load()

        XCTAssertEqual(viewModel.state.dueSoonRows.first?.dueDate, date("2026-06-20"))
        XCTAssertEqual(viewModel.state.dueSoonRows.first?.subtitle, "订阅到期")
    }

    func testHomeViewModelMarksMissingExchangeRateIncomplete() {
        let category = sampleCategory()
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [sampleRecord(categoryId: category.id, currency: .USD)]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar()
        )
        viewModel.load()
        XCTAssertTrue(viewModel.state.isStatisticsIncomplete)
        XCTAssertNil(viewModel.state.monthTotal)
    }

    func testHomeViewModelYearAmortizationCountsPaidOccurrencesThroughToday() throws {
        let category = sampleCategory()
        let iCloud = sampleRecord(
            name: "iCloud+",
            serviceKey: "icloud-plus",
            categoryId: category.id,
            amount: 40,
            currency: .CNY,
            cycle: .quarterly,
            start: date("2025-08-12")
        )
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [iCloud]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar(),
            now: { date("2026-06-08") }
        )

        viewModel.load()

        let yearCard = try XCTUnwrap(viewModel.state.summaryCards.first { $0.id == "year" })
        let iCloudDetail = try XCTUnwrap(yearCard.detailRows.first { $0.name == "iCloud+" })
        XCTAssertEqual(NSDecimalNumber(decimal: iCloudDetail.money.amount).doubleValue, 98.26, accuracy: 0.01)
    }

    func testHomeViewModelYearAmortizationIncludesFullOneTimeWindowInsideYear() throws {
        let category = sampleCategory()
        let chatGPT = sampleRecord(
            name: "ChatGPT",
            serviceKey: "chatgpt",
            categoryId: category.id,
            amount: 19.99,
            currency: .USD,
            cycle: .oneTime,
            start: date("2026-06-06"),
            end: date("2026-07-05")
        )
        var paidRecord = chatGPT
        paidRecord.paidAmount = Decimal(string: "135.99")
        paidRecord.paidCurrency = .CNY

        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [paidRecord]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar(),
            now: { date("2026-06-08") }
        )

        viewModel.load()

        let yearCard = try XCTUnwrap(viewModel.state.summaryCards.first { $0.id == "year" })
        let chatGPTDetail = try XCTUnwrap(yearCard.detailRows.first { $0.name == "ChatGPT" })
        XCTAssertEqual(chatGPTDetail.money.amount, Decimal(string: "135.99"))
    }

    func testHomeViewModelMonthAmortizationUsesFullMonthForOpenEndedSubscriptions() throws {
        let category = sampleCategory()
        let iCloud = sampleRecord(
            name: "iCloud+",
            serviceKey: "icloud-plus",
            categoryId: category.id,
            amount: 40,
            currency: .CNY,
            cycle: .quarterly,
            start: date("2025-08-12")
        )
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [iCloud]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar(),
            now: { date("2026-06-08") }
        )

        viewModel.load()

        let monthCard = try XCTUnwrap(viewModel.state.summaryCards.first { $0.id == "month" })
        let iCloudDetail = try XCTUnwrap(monthCard.detailRows.first { $0.name == "iCloud+" })
        XCTAssertEqual(NSDecimalNumber(decimal: iCloudDetail.money.amount).doubleValue, 13.04, accuracy: 0.01)
    }

    func testHomeViewModelMonthAmortizationCountsShortOneTimePaymentInBillingMonth() throws {
        let category = sampleCategory()
        let chatGPT = sampleRecord(
            name: "ChatGPT",
            serviceKey: "chatgpt",
            categoryId: category.id,
            amount: 19.99,
            currency: .USD,
            cycle: .oneTime,
            start: date("2026-06-06"),
            end: date("2026-07-05")
        )
        var paidRecord = chatGPT
        paidRecord.paidAmount = Decimal(string: "135.99")
        paidRecord.paidCurrency = .CNY
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [paidRecord]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar(),
            now: { date("2026-06-08") }
        )

        viewModel.load()

        let monthCard = try XCTUnwrap(viewModel.state.summaryCards.first { $0.id == "month" })
        let chatGPTDetail = try XCTUnwrap(monthCard.detailRows.first { $0.name == "ChatGPT" })
        XCTAssertEqual(chatGPTDetail.money.amount, Decimal(string: "135.99"))
    }

    func testHomeViewModelMonthAmortizationUsesLeapYearFebruaryLength() throws {
        let category = sampleCategory()
        let iCloud = sampleRecord(
            name: "iCloud+",
            serviceKey: "icloud-plus",
            categoryId: category.id,
            amount: 90,
            currency: .CNY,
            cycle: .quarterly,
            start: date("2024-02-01")
        )
        let viewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [iCloud]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2024-02-01"))),
            calendar: fixedCalendar(),
            now: { date("2024-02-08") }
        )

        viewModel.load()

        let monthCard = try XCTUnwrap(viewModel.state.summaryCards.first { $0.id == "month" })
        let iCloudDetail = try XCTUnwrap(monthCard.detailRows.first { $0.name == "iCloud+" })
        XCTAssertEqual(NSDecimalNumber(decimal: iCloudDetail.money.amount).doubleValue, 29, accuracy: 0.01)
    }

    func testHomeViewModelDistinguishesNoRecordsFromNoActiveRecords() {
        let category = sampleCategory()
        let emptyViewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: []),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar()
        )
        emptyViewModel.load()

        let historyViewModel = HomeViewModel(
            subscriptions: InMemorySubscriptionRepository(records: [
                sampleRecord(categoryId: category.id, currency: .CNY, status: .cancelled)
            ]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar()
        )
        historyViewModel.load()

        XCTAssertFalse(emptyViewModel.state.hasAnySubscriptions)
        XCTAssertTrue(historyViewModel.state.hasAnySubscriptions)
        XCTAssertEqual(historyViewModel.state.activeCount, 0)
        XCTAssertTrue(historyViewModel.state.subscriptionRows.isEmpty)
    }

    func testSettingsViewModelSavesPrimaryCurrencyAndReminder() {
        let repository = InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01")))
        let viewModel = SettingsViewModel(repository: repository)
        viewModel.load()

        viewModel.setPrimaryCurrency(.USD)
        XCTAssertEqual(repository.settings.primaryDisplayCurrency, .USD)
        XCTAssertEqual(viewModel.lastChange, .primaryCurrencyChanged)

        viewModel.setDefaultReminder(enabled: false, daysBefore: 3)
        XCTAssertEqual(repository.settings.defaultReminderConfig, ReminderConfig(isEnabled: false, daysBefore: 3))
        XCTAssertEqual(viewModel.lastChange, .reminderSettingsChanged)
    }

    func testSettingsViewModelSavesManualExchangeRate() {
        let rates = InMemoryExchangeRateRepository(rates: [])
        let viewModel = SettingsViewModel(
            repository: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            exchangeRates: rates
        )
        viewModel.manualRateBase = .USD
        viewModel.manualRateTarget = .CNY
        viewModel.manualRateDate = date("2026-01-15")
        viewModel.manualRateValue = "7.2"

        viewModel.saveManualRate()

        XCTAssertEqual(rates.rates.count, 1)
        XCTAssertEqual(rates.rates.first?.rate, Decimal(string: "7.2"))
        XCTAssertEqual(rates.rates.first?.source, .manual)
        XCTAssertEqual(viewModel.lastChange, .exchangeRateChanged)
    }

    func testCategoryManagementCreatesEditsSortsAndArchivesCustomCategory() throws {
        let existing = sampleCategory()
        let categories = InMemoryCategoryRepository(categories: [existing])
        let subscriptions = InMemorySubscriptionRepository(records: [sampleRecord(categoryId: existing.id, currency: .CNY)])
        let viewModel = CategoryManagementViewModel(categories: categories, subscriptions: subscriptions)

        viewModel.editor = CategoryEditorState(name: "  阅读  ", iconName: "book", colorToken: "custom")
        viewModel.saveEditor()
        let created = try XCTUnwrap(categories.categories.first { $0.name == "阅读" })
        XCTAssertFalse(created.isSystem)

        viewModel.beginEditing(CategoryManagementRowState(
            id: created.id,
            name: created.name,
            iconName: created.iconName,
            colorToken: created.colorToken,
            sortOrder: created.sortOrder,
            isSystem: created.isSystem,
            isArchived: created.isArchived,
            usageCount: 0
        ))
        viewModel.editor.name = "阅读资料"
        viewModel.editor.iconName = "doc.text"
        viewModel.saveEditor()
        XCTAssertEqual(categories.categories.first { $0.id == created.id }?.name, "阅读资料")
        XCTAssertEqual(categories.categories.first { $0.id == created.id }?.iconName, "doc.text")

        viewModel.load()
        viewModel.move(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(categories.categories.first { $0.id == created.id }?.sortOrder, 0)

        viewModel.archive(id: created.id)
        XCTAssertTrue(categories.categories.first { $0.id == created.id }?.isArchived == true)
    }

    func testSettingsViewModelBackupAndMergeRestore() throws {
        let category = sampleCategory()
        let settings = InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01")))
        let subscriptions = InMemorySubscriptionRepository(records: [sampleRecord(categoryId: category.id, currency: .CNY)])
        let service = BackupRestoreService(
            settings: settings,
            subscriptions: subscriptions,
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: [])
        )
        let viewModel = SettingsViewModel(repository: settings, backupRestore: service)

        XCTAssertTrue(viewModel.prepareBackup())
        XCTAssertNotNil(viewModel.backupData)
        XCTAssertNotNil(settings.settings.lastBackupAt)

        let incoming = sampleRecord(name: "Netflix", serviceKey: "netflix", categoryId: category.id, currency: .CNY)
        let payload = BackupPayload(settings: settings.settings, subscriptions: [incoming], categories: [category], serviceTemplates: [], exchangeRates: [], notificationSettings: [:])
        let data = try BackupEncoderDecoder().encode(payload: payload, createdAt: date("2026-01-02"))
        XCTAssertTrue(viewModel.previewRestore(data: data))
        viewModel.restore(data: data, mode: .merge)
        XCTAssertEqual(viewModel.lastChange, .dataRestored)
        XCTAssertTrue(subscriptions.records.contains(where: { $0.serviceKey == "netflix" }))
    }

    func testOverwriteRestoreReplacesLocalRecords() throws {
        let category = sampleCategory()
        let settings = InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01")))
        let subscriptions = InMemorySubscriptionRepository(records: [sampleRecord(categoryId: category.id, currency: .CNY)])
        let service = BackupRestoreService(
            settings: settings,
            subscriptions: subscriptions,
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: [])
        )
        let incoming = sampleRecord(name: "Netflix", serviceKey: "netflix", categoryId: category.id, currency: .CNY)
        let payload = BackupPayload(settings: settings.settings, subscriptions: [incoming], categories: [category], serviceTemplates: [], exchangeRates: [], notificationSettings: [:])
        let data = try BackupEncoderDecoder().encode(payload: payload, createdAt: date("2026-01-02"))

        try service.restore(data: data, mode: .overwrite)

        XCTAssertEqual(subscriptions.records.map(\.serviceKey), ["netflix"])
    }

    func testSubscriptionUpdateKeepsHistoryIdentityAndChangesAmount() throws {
        let category = sampleCategory()
        let original = sampleRecord(categoryId: category.id, amount: 20, currency: .USD)
        let subscriptions = InMemorySubscriptionRepository(records: [original])
        let service = SubscriptionCommandService(
            repository: subscriptions,
            categories: InMemoryCategoryRepository(categories: [category])
        )
        let draft = SubscriptionDraft(
            serviceName: "ChatGPT Plus",
            serviceKey: nil,
            categoryId: category.id,
            listedAmount: 25,
            listedCurrency: .USD,
            paidAmount: nil,
            paidCurrency: nil,
            billingCycle: .monthly,
            startDate: original.startDate,
            endDate: nil,
            nextBillingDate: nil,
            isNextBillingDateManual: false,
            status: .active,
            paymentMethod: nil,
            reminderConfig: .defaultEnabled,
            websiteURL: nil,
            note: nil
        )

        let updated = try service.update(id: original.id, from: draft, now: date("2026-02-01"))

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.serviceKey, original.serviceKey)
        XCTAssertEqual(subscriptions.records.count, 1)
        XCTAssertEqual(subscriptions.records.first?.listedAmount, 25)
    }

    func testSubscriptionFormAppliesTemplateAndSavesStableServiceKey() throws {
        let category = sampleCategory()
        let template = ServiceTemplate(
            id: UUID(),
            serviceName: "ChatGPT",
            serviceKey: "chatgpt",
            categoryId: category.id,
            defaultCurrency: .USD,
            defaultCycle: .monthly,
            iconStyle: IconStyle(systemName: "sparkles", colorToken: "ai"),
            note: nil,
            websiteURL: URL(string: "https://chatgpt.com"),
            isSystem: true,
            sortOrder: 0,
            createdAt: date("2026-01-01"),
            updatedAt: date("2026-01-01")
        )
        let subscriptions = InMemorySubscriptionRepository(records: [])
        let viewModel = SubscriptionFormViewModel(
            commandService: SubscriptionCommandService(
                repository: subscriptions,
                categories: InMemoryCategoryRepository(categories: [category])
            ),
            categoryRepository: InMemoryCategoryRepository(categories: [category]),
            templateRepository: InMemoryServiceTemplateRepository(templates: [template])
        )

        viewModel.load()
        viewModel.selectTemplate(serviceKey: "chatgpt")
        viewModel.listedAmount = "20"
        _ = try viewModel.save()

        XCTAssertEqual(viewModel.serviceName, "ChatGPT")
        XCTAssertEqual(viewModel.selectedCategoryId, category.id)
        XCTAssertEqual(viewModel.listedCurrency, .USD)
        XCTAssertEqual(subscriptions.records.first?.serviceKey, "chatgpt")
    }

    func testSubscriptionFormConvertsOneTimeToRecurringCleanly() {
        let category = sampleCategory()
        let existing = sampleRecord(
            categoryId: category.id,
            amount: 100,
            currency: .CNY,
            cycle: .oneTime,
            start: date("2026-06-01"),
            end: date("2026-06-30"),
            status: .oneTime
        )
        let viewModel = SubscriptionFormViewModel(
            commandService: SubscriptionCommandService(
                repository: InMemorySubscriptionRepository(records: [existing]),
                categories: InMemoryCategoryRepository(categories: [category])
            ),
            categoryRepository: InMemoryCategoryRepository(categories: [category]),
            existingRecord: existing
        )

        viewModel.load()
        viewModel.billingCycle = .yearly
        viewModel.billingCycleChanged(from: .oneTime, to: .yearly)

        XCTAssertEqual(viewModel.status, .active)
        XCTAssertFalse(viewModel.hasEndDate)
        XCTAssertFalse(viewModel.hasManualNextBillingDate)
    }

    func testSubscriptionFormStatusChangesKeepDatesConsistent() {
        let category = sampleCategory()
        let existing = sampleRecord(categoryId: category.id, amount: 20, currency: .CNY, start: date("2026-06-01"))
        let viewModel = SubscriptionFormViewModel(
            commandService: SubscriptionCommandService(
                repository: InMemorySubscriptionRepository(records: [existing]),
                categories: InMemoryCategoryRepository(categories: [category])
            ),
            categoryRepository: InMemoryCategoryRepository(categories: [category]),
            existingRecord: existing
        )

        viewModel.load()
        viewModel.status = .cancelled
        viewModel.statusChanged(from: .active, to: .cancelled)
        XCTAssertTrue(viewModel.hasEndDate)
        XCTAssertFalse(viewModel.hasManualNextBillingDate)

        viewModel.status = .oneTime
        viewModel.statusChanged(from: .cancelled, to: .oneTime)
        XCTAssertEqual(viewModel.billingCycle, .oneTime)
        XCTAssertTrue(viewModel.hasEndDate)

        viewModel.status = .active
        viewModel.statusChanged(from: .oneTime, to: .active)
        XCTAssertEqual(viewModel.billingCycle, .monthly)
        XCTAssertFalse(viewModel.hasEndDate)
    }

    func testStatisticsQueryServiceBuildsServiceRanking() throws {
        let category = sampleCategory()
        let settings = AppSettings.defaults(now: date("2026-01-01"))
        let service = StatisticsQueryService(
            subscriptions: InMemorySubscriptionRepository(records: [
                sampleRecord(categoryId: category.id, amount: 10, currency: .CNY, start: date("2026-01-01")),
                sampleRecord(name: "ChatGPT Old", serviceKey: "chatgpt", categoryId: category.id, amount: 20, currency: .CNY, start: date("2026-02-01"), status: .cancelled)
            ]),
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: settings),
            calendar: fixedCalendar()
        )
        let state = try service.pageState(now: date("2026-02-15"))
        XCTAssertEqual(state.services.first?.id, "chatgpt")
        XCTAssertEqual(state.services.first?.name, "ChatGPT")
    }

    func testServiceAggregationCommandMovesRecordWithoutChangingHistoryFields() throws {
        let category = sampleCategory()
        let original = sampleRecord(categoryId: category.id, amount: 20, currency: .CNY, start: date("2026-01-01"), status: .cancelled)
        let other = sampleRecord(name: "Claude", serviceKey: "claude", categoryId: category.id, amount: 30, currency: .CNY, start: date("2026-02-01"))
        let repository = InMemorySubscriptionRepository(records: [original, other])
        let command = ServiceAggregationCommandService(subscriptions: repository)

        let moved = try command.move(recordId: original.id, toExistingServiceKey: "claude")

        XCTAssertEqual(repository.records.count, 2)
        XCTAssertEqual(moved.serviceKey, "claude")
        XCTAssertEqual(moved.listedAmount, original.listedAmount)
        XCTAssertEqual(moved.startDate, original.startDate)
        XCTAssertEqual(moved.status, original.status)
        XCTAssertEqual(moved.updatedAt, original.updatedAt)
    }

    func testServiceAggregationCommandCanCreateNewGroupForSingleRecord() throws {
        let category = sampleCategory()
        let original = sampleRecord(categoryId: category.id, currency: .CNY)
        let repository = InMemorySubscriptionRepository(records: [original])
        let command = ServiceAggregationCommandService(subscriptions: repository)

        let moved = try command.createNewGroup(for: original.id)

        XCTAssertEqual(repository.records.count, 1)
        XCTAssertNotEqual(moved.serviceKey, original.serviceKey)
        XCTAssertTrue(moved.serviceKey.hasPrefix("local-chatgpt-"))
        XCTAssertEqual(moved.listedAmount, original.listedAmount)
        XCTAssertEqual(moved.startDate, original.startDate)
        XCTAssertEqual(moved.status, original.status)
        XCTAssertEqual(moved.updatedAt, original.updatedAt)
    }

    func testServiceAggregationMoveChangesStatisticsServiceGrouping() throws {
        let category = sampleCategory()
        let first = sampleRecord(categoryId: category.id, amount: 10, currency: .CNY, start: date("2026-01-01"))
        let second = sampleRecord(name: "Claude", serviceKey: "claude", categoryId: category.id, amount: 20, currency: .CNY, start: date("2026-01-01"))
        let repository = InMemorySubscriptionRepository(records: [first, second])
        let command = ServiceAggregationCommandService(subscriptions: repository)
        _ = try command.move(recordId: second.id, toExistingServiceKey: "chatgpt")

        let service = StatisticsQueryService(
            subscriptions: repository,
            categories: InMemoryCategoryRepository(categories: [category]),
            templates: InMemoryServiceTemplateRepository(templates: []),
            exchangeRates: InMemoryExchangeRateRepository(rates: []),
            settings: InMemorySettingsRepository(settings: .defaults(now: date("2026-01-01"))),
            calendar: fixedCalendar()
        )
        let state = try service.pageState(now: date("2026-01-15"))

        XCTAssertEqual(state.services.map(\.id), ["chatgpt"])
    }
}

final class InMemorySubscriptionRepository: SubscriptionRepository {
    var records: [SubscriptionRecord]

    init(records: [SubscriptionRecord]) {
        self.records = records
    }

    func fetchAll() throws -> [SubscriptionRecord] { records }
    func fetch(id: UUID) throws -> SubscriptionRecord? { records.first { $0.id == id } }
    func fetchActive() throws -> [SubscriptionRecord] { records.filter(\.status.isOngoing) }
    func fetchByServiceKey(_ serviceKey: String) throws -> [SubscriptionRecord] { records.filter { $0.serviceKey == serviceKey } }
    func save(_ record: SubscriptionRecord) throws {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }
    func saveMany(_ records: [SubscriptionRecord]) throws { self.records.append(contentsOf: records) }
    func delete(id: UUID) throws { records.removeAll { $0.id == id } }
    func replaceAll(_ records: [SubscriptionRecord]) throws { self.records = records }
}

final class InMemorySettingsRepository: AppSettingsRepository {
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func fetch() throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
    }
}

final class InMemoryCategoryRepository: CategoryRepository {
    var categories: [Subly.Category]

    init(categories: [Subly.Category]) {
        self.categories = categories
    }

    func fetchAll(includeArchived: Bool) throws -> [Subly.Category] {
        includeArchived ? categories : categories.filter { !$0.isArchived }
    }

    func fetch(id: UUID) throws -> Subly.Category? {
        categories.first { $0.id == id }
    }

    func save(_ category: Subly.Category) throws {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
    }

    func saveMany(_ categories: [Subly.Category]) throws {
        self.categories.append(contentsOf: categories)
    }

    func archive(id: UUID) throws {
        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].isArchived = true
        }
    }

    func replaceAll(_ categories: [Subly.Category]) throws {
        self.categories = categories
    }
}

final class InMemoryExchangeRateRepository: ExchangeRateRepository {
    var rates: [ExchangeRate]

    init(rates: [ExchangeRate]) {
        self.rates = rates
    }

    func fetchAll() throws -> [ExchangeRate] {
        rates
    }

    func fetchRate(base: CurrencyCode, target: CurrencyCode, on date: Date, preferManual: Bool) throws -> ExchangeRate? {
        rates.first { $0.baseCurrency == base && $0.targetCurrency == target }
    }

    func fetchLatestRate(base: CurrencyCode, target: CurrencyCode, upTo date: Date, preferManual: Bool) throws -> ExchangeRate? {
        rates.first { $0.baseCurrency == base && $0.targetCurrency == target }
    }

    func save(_ rate: ExchangeRate) throws {
        if let index = rates.firstIndex(where: { $0.id == rate.id }) {
            rates[index] = rate
        } else {
            rates.append(rate)
        }
    }

    func saveMany(_ rates: [ExchangeRate]) throws {
        self.rates.append(contentsOf: rates)
    }

    func replaceAll(_ rates: [ExchangeRate]) throws {
        self.rates = rates
    }
}

final class InMemoryServiceTemplateRepository: ServiceTemplateRepository {
    var templates: [ServiceTemplate]

    init(templates: [ServiceTemplate]) {
        self.templates = templates
    }

    func fetchAll() throws -> [ServiceTemplate] {
        templates
    }

    func fetch(serviceKey: String) throws -> ServiceTemplate? {
        templates.first { $0.serviceKey == serviceKey }
    }

    func save(_ template: ServiceTemplate) throws {
        templates.append(template)
    }

    func saveMany(_ templates: [ServiceTemplate]) throws {
        self.templates.append(contentsOf: templates)
    }

    func replaceAll(_ templates: [ServiceTemplate]) throws {
        self.templates = templates
    }
}
