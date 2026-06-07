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
            return [makeOccurrence(record: record, coverage: boundedRange, billingDate: record.startDate, queryRange: serviceRange)]
        }

        var results: [BillingOccurrence] = []
        var cycleIndex = 0
        var cycleStart = try cycleBoundary(record: record, index: cycleIndex)
        var cycleEnd = try cycleBoundary(record: record, index: cycleIndex + 1)

        while cycleEnd <= range.start {
            cycleIndex += 1
            cycleStart = cycleEnd
            cycleEnd = try cycleBoundary(record: record, index: cycleIndex + 1)
            guard cycleEnd > cycleStart else { return results }
        }

        while cycleStart < range.endExclusive {
            let cycleRange = try DateRange(start: cycleStart, endExclusive: cycleEnd)
            if let clippedToService = cycleRange.intersection(serviceRange),
               let clippedToQuery = clippedToService.intersection(range) {
                results.append(makeOccurrence(record: record, coverage: clippedToQuery, billingDate: cycleStart, queryRange: cycleRange))
            }
            guard cycleEnd > cycleStart else { break }
            cycleIndex += 1
            cycleStart = cycleEnd
            cycleEnd = try cycleBoundary(record: record, index: cycleIndex + 1)
        }
        return results.filter { $0.coverage.intersection(boundedRange) != nil }
    }

    func nextBillingDate(for record: SubscriptionRecord, after date: Date) throws -> Date? {
        guard record.status.allowsFutureBillingReminder else { return nil }
        if record.isNextBillingDateManual {
            return record.nextBillingDate
        }
        try record.billingCycle.validate()
        var cycleIndex = 0
        var candidate = try cycleBoundary(record: record, index: cycleIndex)
        let afterDay = calendar.startOfDay(for: date)
        while candidate < afterDay {
            cycleIndex += 1
            candidate = try cycleBoundary(record: record, index: cycleIndex)
        }
        if let endDate = record.endDate, candidate > calendar.startOfDay(for: endDate) {
            return nil
        }
        return candidate
    }

    private func cycleBoundary(record: SubscriptionRecord, index: Int) throws -> Date {
        let start = calendar.startOfDay(for: record.startDate)
        guard index > 0 else { return start }

        switch record.billingCycle {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * index, to: start)!
        case .monthly:
            return calendar.date(byAdding: .month, value: index, to: start)!
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3 * index, to: start)!
        case .halfYearly:
            return calendar.date(byAdding: .month, value: 6 * index, to: start)!
        case .yearly:
            return calendar.date(byAdding: .year, value: index, to: start)!
        case .customDays(let days):
            guard days > 0 else { throw ValidationError.invalidBillingCycle }
            return calendar.date(byAdding: .day, value: days * index, to: start)!
        case .oneTime:
            guard let endDate = record.endDate else { throw SublyError.validation(.invalidDateRange) }
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        case .trial(let days):
            if let endDate = record.endDate {
                guard index == 1 else {
                    return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
                }
                return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
            }
            return calendar.date(byAdding: .day, value: (days ?? 7) * index, to: start)!
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
