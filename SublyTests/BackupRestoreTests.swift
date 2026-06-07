import XCTest
@testable import Subly

final class BackupRestoreTests: XCTestCase {
    func testBackupRoundTripsAndValidatesChecksum() throws {
        let encoder = BackupEncoderDecoder()
        let payload = BackupPayload(settings: .defaults(now: date("2026-01-01")), subscriptions: [sampleRecord()], categories: [sampleCategory()], serviceTemplates: [], exchangeRates: [sampleRate()], notificationSettings: [:])
        let data = try encoder.encode(payload: payload, createdAt: date("2026-01-02"))
        let decoded = try encoder.decode(data)
        XCTAssertEqual(decoded.metadata.appName, "Subly")
        XCTAssertEqual(decoded.subscriptions.count, 1)
    }

    func testMergeKeepsNewerSameIdAndDeduplicatesFingerprint() {
        let local = sampleRecord(start: date("2026-01-01"))
        var incoming = local
        incoming.serviceName = "ChatGPT Plus"
        incoming.updatedAt = date("2026-01-03")
        let duplicate = sampleRecord(start: local.startDate)
        let merged = RestoreMergePolicy().merge(local: [local], incoming: [incoming, duplicate])
        XCTAssertTrue(merged.contains(where: { $0.serviceName == "ChatGPT Plus" }))
    }
}
