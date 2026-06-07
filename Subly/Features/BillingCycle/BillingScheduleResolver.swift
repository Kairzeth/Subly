import Foundation

struct BillingOccurrence: Equatable, Identifiable {
    var id: UUID
    var recordId: UUID
    var serviceKey: String
    var money: Money
    var coverage: DateRange
    var billingDate: Date
    var totalCycleDays: Int
    var intersectedDays: Int
}

protocol BillingScheduleResolving {
    func occurrences(for record: SubscriptionRecord, in range: DateRange) throws -> [BillingOccurrence]
    func nextBillingDate(for record: SubscriptionRecord, after date: Date) throws -> Date?
}

struct BillingScheduleResolver: BillingScheduleResolving {
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func occurrences(for record: SubscriptionRecord, in range: DateRange) throws -> [BillingOccurrence] {
        try record.billingCycle.validate()
        let serviceRange = try DateRange.fromUserDates(start: record.startDate, inclusiveEnd: record.endDate, calendar: calendar)
        guard let boundedRange = serviceRange.intersection(range) else { return [] }

        if record.billingCycle == .oneTime {
            guard record.endDate != nil else { throw SublyError.validation(.invalidDateRange) }
            return [makeOccurrence(record: record, coverage: boundedRange, billingDate: record.startDate, queryRange: range)]
        }

        var results: [BillingOccurrence] = []
        var cycleStart = calendar.startOfDay(for: record.startDate)
        while cycleStart < range.endExclusive {
            let cycleEnd = try nextCycleStart(after: cycleStart, cycle: record.billingCycle, record: record)
            let cycleRange = try DateRange(start: cycleStart, endExclusive: cycleEnd)
            if let clippedToService = cycleRange.intersection(serviceRange),
               let clippedToQuery = clippedToService.intersection(range) {
                results.append(makeOccurrence(record: record, coverage: clippedToQuery, billingDate: cycleStart, queryRange: cycleRange))
            }
            guard cycleEnd > cycleStart else { break }
            cycleStart = cycleEnd
        }
        return results.filter { $0.coverage.intersection(boundedRange) != nil }
    }

    func nextBillingDate(for record: SubscriptionRecord, after date: Date) throws -> Date? {
        guard record.status.allowsFutureBillingReminder else { return nil }
        if record.isNextBillingDateManual {
            return record.nextBillingDate
        }
        try record.billingCycle.validate()
        var candidate = calendar.startOfDay(for: record.startDate)
        let afterDay = calendar.startOfDay(for: date)
        while candidate < afterDay {
            candidate = try nextCycleStart(after: candidate, cycle: record.billingCycle, record: record)
        }
        if let endDate = record.endDate, candidate > calendar.startOfDay(for: endDate) {
            return nil
        }
        return candidate
    }

    private func nextCycleStart(after date: Date, cycle: BillingCycle, record: SubscriptionRecord) throws -> Date {
        switch cycle {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)!
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)!
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date)!
        case .halfYearly:
            return calendar.date(byAdding: .month, value: 6, to: date)!
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)!
        case .customDays(let days):
            guard days > 0 else { throw ValidationError.invalidBillingCycle }
            return calendar.date(byAdding: .day, value: days, to: date)!
        case .oneTime:
            guard let endDate = record.endDate else { throw SublyError.validation(.invalidDateRange) }
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        case .trial(let days):
            if let endDate = record.endDate {
                return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
            }
            return calendar.date(byAdding: .day, value: days ?? 7, to: date)!
        }
    }

    private func makeOccurrence(record: SubscriptionRecord, coverage: DateRange, billingDate: Date, queryRange: DateRange) -> BillingOccurrence {
        BillingOccurrence(
            id: UUID(),
            recordId: record.id,
            serviceKey: record.serviceKey,
            money: record.effectiveMoney,
            coverage: coverage,
            billingDate: billingDate,
            totalCycleDays: max(1, queryRange.coveredDays(calendar: calendar)),
            intersectedDays: coverage.coveredDays(calendar: calendar)
        )
    }
}
