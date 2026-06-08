import Foundation

struct StatisticsResult: Equatable {
    var total: Money?
    var isIncomplete: Bool
    var missingRates: [String]
    var categoryTotals: [UUID: Decimal]
    var serviceTotals: [String: Decimal]
}

enum AmortizationScope: Equatable {
    case proportional
    case monthly
    case yearly(cutoff: Date)
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
        scope: AmortizationScope = .proportional
    ) -> StatisticsResult {
        var total: Decimal = 0
        var categoryTotals: [UUID: Decimal] = [:]
        var serviceTotals: [String: Decimal] = [:]
        var missing: [String] = []

        for record in records {
            do {
                let occurrences = try scheduleResolver.occurrences(for: record, in: range)
                for occurrence in occurrences {
                    let converted = try converter.convert(occurrence.money, to: displayCurrency, on: occurrence.billingDate)
                    let amortized = amortizedAmount(
                        record: record,
                        convertedAmount: converted.amount,
                        occurrence: occurrence,
                        range: range,
                        scope: scope
                    )
                    guard amortized > 0 else { continue }
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

    private func amortizedAmount(
        record: SubscriptionRecord,
        convertedAmount: Decimal,
        occurrence: BillingOccurrence,
        range: DateRange,
        scope: AmortizationScope
    ) -> Decimal {
        switch scope {
        case .proportional:
            return proportionalAmount(convertedAmount: convertedAmount, occurrence: occurrence)
        case .monthly:
            guard record.billingCycle == .oneTime else {
                return proportionalAmount(convertedAmount: convertedAmount, occurrence: occurrence)
            }
            let monthDays = max(1, range.coveredDays(calendar: calendar))
            guard occurrence.totalCycleDays <= monthDays else {
                return proportionalAmount(convertedAmount: convertedAmount, occurrence: occurrence)
            }
            return range.containsDay(occurrence.billingDate, calendar: calendar) ? convertedAmount : 0
        case .yearly(let cutoff):
            guard calendar.startOfDay(for: occurrence.billingDate) <= calendar.startOfDay(for: cutoff) else { return 0 }
            guard occurrence.fullCoverage.spansMultipleYears(calendar: calendar) else {
                return range.containsDay(occurrence.billingDate, calendar: calendar) ? convertedAmount : 0
            }
            return proportionalAmount(convertedAmount: convertedAmount, occurrence: occurrence)
        }
    }

    private func proportionalAmount(convertedAmount: Decimal, occurrence: BillingOccurrence) -> Decimal {
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

private extension DateRange {
    func containsDay(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= start && day < endExclusive
    }

    func spansMultipleYears(calendar: Calendar) -> Bool {
        let startYear = calendar.component(.year, from: start)
        guard let lastCoveredDay = calendar.date(byAdding: .day, value: -1, to: endExclusive) else { return false }
        let endYear = calendar.component(.year, from: lastCoveredDay)
        return startYear != endYear
    }
}
