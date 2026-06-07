import CryptoKit
import Foundation

struct SublyBackupFile: Codable, Equatable {
    var metadata: BackupMetadata
    var settings: AppSettings
    var subscriptions: [SubscriptionRecord]
    var categories: [Category]
    var serviceTemplates: [ServiceTemplate]
    var exchangeRates: [ExchangeRate]
    var notificationSettings: [UUID: ReminderConfig]
}

struct BackupPayload: Codable, Equatable {
    var settings: AppSettings
    var subscriptions: [SubscriptionRecord]
    var categories: [Category]
    var serviceTemplates: [ServiceTemplate]
    var exchangeRates: [ExchangeRate]
    var notificationSettings: [UUID: ReminderConfig]
}

enum RestoreMode: String, Codable, Equatable {
    case merge
    case overwrite
}

struct RestorePreview: Equatable {
    var createdAt: Date
    var recordCount: Int
    var dataVersion: Int
    var appVersion: String
}

struct BackupRestoreSnapshot {
    var settings: AppSettings
    var subscriptions: [SubscriptionRecord]
    var categories: [Category]
    var serviceTemplates: [ServiceTemplate]
    var exchangeRates: [ExchangeRate]
}

@MainActor
struct BackupRestoreService {
    var settings: AppSettingsRepository
    var subscriptions: SubscriptionRepository
    var categories: CategoryRepository
    var templates: ServiceTemplateRepository
    var exchangeRates: ExchangeRateRepository
    var reminderSync: ReminderSyncService?
    var encoderDecoder = BackupEncoderDecoder()
    var mergePolicy = RestoreMergePolicy()

    func exportBackup(now: Date = Date()) throws -> Data {
        let payload = BackupPayload(
            settings: try settings.fetch(),
            subscriptions: try subscriptions.fetchAll(),
            categories: try categories.fetchAll(includeArchived: true),
            serviceTemplates: try templates.fetchAll(),
            exchangeRates: try exchangeRates.fetchAll(),
            notificationSettings: [:]
        )
        let data = try encoderDecoder.encode(payload: payload, createdAt: now)
        var updatedSettings = payload.settings
        updatedSettings.lastBackupAt = now
        updatedSettings.updatedAt = now
        try settings.save(updatedSettings)
        return data
    }

    func preview(data: Data) throws -> RestorePreview {
        let file = try encoderDecoder.decode(data)
        return RestorePreview(
            createdAt: file.metadata.createdAt,
            recordCount: file.metadata.recordCount,
            dataVersion: file.metadata.dataVersion,
            appVersion: file.metadata.appVersion
        )
    }

    func restore(data: Data, mode: RestoreMode = .merge) throws {
        let file = try encoderDecoder.decode(data)
        try validate(file)
        switch mode {
        case .merge:
            try merge(file)
        case .overwrite:
            try overwrite(file)
        }
        if let reminderSync {
            Task { try? await reminderSync.rebuildAll() }
        }
    }

    private func merge(_ file: SublyBackupFile) throws {
        let mergedSubscriptions = mergePolicy.merge(local: try subscriptions.fetchAll(), incoming: file.subscriptions)
        try subscriptions.saveMany(mergedSubscriptions)
        try mergeCategories(file.categories)
        try mergeTemplates(file.serviceTemplates)
        try mergeExchangeRates(file.exchangeRates)
        var mergedSettings = try settings.fetch()
        if file.settings.updatedAt > mergedSettings.updatedAt {
            mergedSettings.primaryDisplayCurrency = file.settings.primaryDisplayCurrency
            mergedSettings.defaultReminderConfig = file.settings.defaultReminderConfig
            mergedSettings.followSystemAppearance = file.settings.followSystemAppearance
            mergedSettings.dataVersion = file.settings.dataVersion
            mergedSettings.updatedAt = Date()
            try settings.save(mergedSettings)
        }
    }

    private func mergeCategories(_ incoming: [Category]) throws {
        let existing = try categories.fetchAll(includeArchived: true)
        let existingIds = Set(existing.map(\.id))
        for category in incoming where !existingIds.contains(category.id) {
            try categories.save(category)
        }
    }

    private func mergeTemplates(_ incoming: [ServiceTemplate]) throws {
        let existingKeys = Set(try templates.fetchAll().map(\.serviceKey))
        let missing = incoming.filter { !existingKeys.contains($0.serviceKey) }
        try templates.saveMany(missing)
    }

    private func mergeExchangeRates(_ incoming: [ExchangeRate]) throws {
        let existing = try exchangeRates.fetchAll()
        let existingKeys = Set(existing.map(rateKey))
        try exchangeRates.saveMany(incoming.filter { !existingKeys.contains(rateKey($0)) })
    }

    private func overwrite(_ file: SublyBackupFile) throws {
        let snapshot = try makeSnapshot()
        do {
            try categories.replaceAll(file.categories)
            try templates.replaceAll(file.serviceTemplates)
            try exchangeRates.replaceAll(file.exchangeRates)
            try subscriptions.replaceAll(file.subscriptions)
            try settings.save(file.settings)
        } catch {
            try? restore(snapshot)
            throw SublyError.restoreFailed(error.localizedDescription)
        }
    }

    private func makeSnapshot() throws -> BackupRestoreSnapshot {
        BackupRestoreSnapshot(
            settings: try settings.fetch(),
            subscriptions: try subscriptions.fetchAll(),
            categories: try categories.fetchAll(includeArchived: true),
            serviceTemplates: try templates.fetchAll(),
            exchangeRates: try exchangeRates.fetchAll()
        )
    }

    private func restore(_ snapshot: BackupRestoreSnapshot) throws {
        try categories.replaceAll(snapshot.categories)
        try templates.replaceAll(snapshot.serviceTemplates)
        try exchangeRates.replaceAll(snapshot.exchangeRates)
        try subscriptions.replaceAll(snapshot.subscriptions)
        try settings.save(snapshot.settings)
    }

    private func rateKey(_ rate: ExchangeRate) -> String {
        "\(rate.baseCurrency.rawValue)|\(rate.targetCurrency.rawValue)|\(rate.date.timeIntervalSince1970)|\(rate.source.rawValue)|\(rate.isManual)"
    }

    private func validate(_ file: SublyBackupFile) throws {
        guard file.metadata.appName == "Subly" else { throw SublyError.backupInvalid("appName") }
        guard file.metadata.dataVersion <= SublyConstants.dataVersion else { throw SublyError.backupInvalid("dataVersion") }
        try file.subscriptions.forEach(validate)
        try file.exchangeRates.forEach(validate)
    }

    private func validate(_ record: SubscriptionRecord) throws {
        guard !record.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SublyError.validation(.emptyName) }
        guard record.listedAmount >= 0 else { throw SublyError.validation(.invalidAmount) }
        if let paidAmount = record.paidAmount, paidAmount < 0 { throw SublyError.validation(.invalidAmount) }
        if record.paidAmount != nil, record.paidCurrency == nil { throw SublyError.validation(.missingPaidCurrency) }
        try record.billingCycle.validate()
        if let endDate = record.endDate, endDate < record.startDate { throw SublyError.validation(.invalidDateRange) }
    }

    private func validate(_ rate: ExchangeRate) throws {
        guard rate.rate > 0 else { throw SublyError.validation(.invalidAmount) }
    }
}

struct BackupEncoderDecoder {
    var appVersion: String = "1.0.0"

    func encode(payload: BackupPayload, createdAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let payloadData = try encoder.encode(payload)
        let checksum = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
        let metadata = BackupMetadata(
            appName: "Subly",
            appVersion: appVersion,
            dataVersion: SublyConstants.dataVersion,
            createdAt: createdAt,
            recordCount: payload.subscriptions.count + payload.categories.count + payload.serviceTemplates.count + payload.exchangeRates.count,
            checksum: checksum
        )
        let file = SublyBackupFile(
            metadata: metadata,
            settings: payload.settings,
            subscriptions: payload.subscriptions,
            categories: payload.categories,
            serviceTemplates: payload.serviceTemplates,
            exchangeRates: payload.exchangeRates,
            notificationSettings: payload.notificationSettings
        )
        return try encoder.encode(file)
    }

    func decode(_ data: Data) throws -> SublyBackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(SublyBackupFile.self, from: data)
        guard file.metadata.appName == "Subly" else { throw SublyError.backupInvalid("appName") }
        guard file.metadata.dataVersion <= SublyConstants.dataVersion else { throw SublyError.backupInvalid("dataVersion") }
        let payload = BackupPayload(
            settings: file.settings,
            subscriptions: file.subscriptions,
            categories: file.categories,
            serviceTemplates: file.serviceTemplates,
            exchangeRates: file.exchangeRates,
            notificationSettings: file.notificationSettings
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let payloadData = try encoder.encode(payload)
        let checksum = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
        guard checksum == file.metadata.checksum else { throw SublyError.backupInvalid("checksum") }
        return file
    }
}

struct RestoreMergePolicy {
    func merge(local: [SubscriptionRecord], incoming: [SubscriptionRecord]) -> [SubscriptionRecord] {
        var mergedById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for record in incoming {
            if let existing = mergedById[record.id] {
                if record.updatedAt > existing.updatedAt {
                    mergedById[record.id] = record
                }
            } else if let duplicate = mergedById.values.first(where: { fingerprint($0) == fingerprint(record) }) {
                if record.updatedAt > duplicate.updatedAt {
                    mergedById.removeValue(forKey: duplicate.id)
                    mergedById[record.id] = record
                }
            } else {
                mergedById[record.id] = record
            }
        }
        return Array(mergedById.values).sorted { $0.createdAt < $1.createdAt }
    }

    func fingerprint(_ record: SubscriptionRecord) -> String {
        [
            record.serviceKey,
            "\(record.startDate.timeIntervalSince1970)",
            "\(record.endDate?.timeIntervalSince1970 ?? 0)",
            "\(record.listedAmount)",
            record.listedCurrency.rawValue,
            record.billingCycle.displayName,
            record.status.rawValue
        ].joined(separator: "|")
    }
}
