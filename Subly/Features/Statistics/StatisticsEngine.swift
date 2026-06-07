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

    func amortizedTotal(records: [SubscriptionRecord], range: DateRange, displayCurrency: CurrencyCode) -> StatisticsResult {
        var total: Decimal = 0
        var categoryTotals: [UUID: Decimal] = [:]
        var serviceTotals: [String: Decimal] = [:]
        var missing: [String] = []

        for record in records {
            do {
                let occurrences = try scheduleResolver.occurrences(for: record, in: range)
                for occurrence in occurrences {
                    let converted = try converter.convert(occurrence.money, to: displayCurrency, on: occurrence.billingDate)
                    let ratio = Decimal(occurrence.intersectedDays) / Decimal(max(1, occurrence.totalCycleDays))
                    let amortized = converted.amount * ratio
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

    func billedTotal(records: [SubscriptionRecord], range: DateRange, displayCurrency: CurrencyCode) -> StatisticsResult {
        var total: Decimal = 0
        var categoryTotals: [UUID: Decimal] = [:]
        var serviceTotals: [String: Decimal] = [:]
        var missing: [String] = []

        for record in records {
            do {
                let occurrences = try scheduleResolver.occurrences(for: record, in: range)
                for occurrence in occurrences {
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
