import Foundation

struct StatisticsResult: Equatable {
    var total: Money?
    var isIncomplete: Bool
    var missingRates: [String]
    var categoryTotals: [UUID: Decimal]
    var serviceTotals: [String: Decimal]
}

struct StatisticsEngine {
    var scheduleResolver: BillingScheduleResolving
    var converter: CurrencyConverter
    var calendar: Calendar

    init(scheduleResolver: BillingScheduleResolving, converter: CurrencyConverter, calendar: Calendar = .current) {
        self.scheduleResolver = scheduleResolver
        self.converter = converter
        self.calendar = calendar
    }

    func amortizedTotal(
        records: [SubscriptionRecord],
        range: DateRange,
        displayCurrency: CurrencyCode,
        cutoffOpenEndedAt cutoffDate: Date? = nil
    ) -> StatisticsResult {
        var total: Decimal = 0
        var categoryTotals: [UUID: Decimal] = [:]
        var serviceTotals: [String: Decimal] = [:]
        var missing: [String] = []

        for record in records {
            do {
                guard let effectiveRange = effectiveAmortizationRange(for: record, in: range, cutoffDate: cutoffDate) else { continue }
                let occurrences = try scheduleResolver.occurrences(for: record, in: effectiveRange)
                for occurrence in occurrences {
                    let converted = try converter.convert(occurrence.money, to: displayCurrency, on: occurrence.billingDate)
                    let amortized = amortizedAmount(
                        convertedAmount: converted.amount,
                        occurrence: occurrence
                    )
                    total += amortized
                    categoryTotals[record.categoryId, default: 0] += amortized
                    serviceTotals[record.serviceKey, default: 0] += amortized
                }
            } catch SublyError.missingExchangeRate(let base, let target) {
                missing.append("\(base.rawValue)-\(target.rawValue)")
            } catch {
                missing.append(record.serviceKey)
            }
        }

        return StatisticsResult(
            total: missing.isEmpty ? Money(unchecked: total, currency: displayCurrency) : nil,
            isIncomplete: !missing.isEmpty,
            missingRates: missing,
            categoryTotals: categoryTotals,
            serviceTotals: serviceTotals
        )
    }

    private func effectiveAmortizationRange(for record: SubscriptionRecord, in range: DateRange, cutoffDate: Date?) -> DateRange? {
        guard record.endDate == nil, let cutoffDate else { return range }
        let cutoffEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cutoffDate))!
        let cappedEnd = min(range.endExclusive, cutoffEnd)
        guard cappedEnd > range.start else { return nil }
        return try? DateRange(start: range.start, endExclusive: cappedEnd)
    }

    private func amortizedAmount(convertedAmount: Decimal, occurrence: BillingOccurrence) -> Decimal {
        let totalCycleDays = max(1, occurrence.totalCycleDays)
        let daysOutsideRange = max(0, totalCycleDays - occurrence.intersectedDays)
        let ratioInsideRange = 1 - Decimal(daysOutsideRange) / Decimal(totalCycleDays)
        return convertedAmount * ratioInsideRange
    }

    func billedTotal(records: [SubscriptionRecord], range: DateRange, displayCurrency: CurrencyCode) -> StatisticsResult {
        var total: Decimal = 0
        var categoryTotals: [UUID: Decimal] = [:]
        var serviceTotals: [String: Decimal] = [:]
        var missing: [String] = []

        for record in records {
            do {
                let occurrences = try scheduleResolver.occurrences(for: record, in: range)
                for occurrence in occurrences {
                    guard occurrence.billingDate >= range.start, occurrence.billingDate < range.endExclusive else { continue }
                    let converted = try converter.convert(occurrence.money, to: displayCurrency, on: occurrence.billingDate)
                    total += converted.amount
                    categoryTotals[record.categoryId, default: 0] += converted.amount
                    serviceTotals[record.serviceKey, default: 0] += converted.amount
                }
            } catch SublyError.missingExchangeRate(let base, let target) {
                missing.append("\(base.rawValue)-\(target.rawValue)")
            } catch {
                missing.append(record.serviceKey)
            }
        }

        return StatisticsResult(
            total: missing.isEmpty ? Money(unchecked: total, currency: displayCurrency) : nil,
            isIncomplete: !missing.isEmpty,
            missingRates: missing,
            categoryTotals: categoryTotals,
            serviceTotals: serviceTotals
        )
    }
}
