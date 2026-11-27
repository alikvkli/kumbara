import Foundation
import Testing
@testable import KumbaraCore

@Suite("Altın birikim planı (specs/10 §7)")
struct SavingsPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func buy(_ quantity: Decimal, _ price: Decimal, _ year: Int, _ month: Int, _ day: Int,
                     asset: AssetCode = .gold(.gram24)) -> Trade {
        Trade(asset: asset, side: .buy, quantity: quantity, unitPrice: price, date: date(year, month, day), usdTRYAtTrade: 40)
    }

    @Test("Her ayın 15'i 2 gram: 12 vadenin 10'unda alım (AC-I7-1)")
    func adherence() {
        let plan = SavingsPlanRule(asset: .gold(.gram24), target: .quantity(2),
                                   trigger: .schedule(.monthly(day: 15)), start: date(2025, 12, 1))
        // Aralık 2025 … Kasım 2026: 12 vade. Mart ve Temmuz atlandı; Haziran alımı 2 gün geç.
        var trades: [Trade] = []
        for (year, month) in [(2025, 12), (2026, 1), (2026, 2), (2026, 4), (2026, 5), (2026, 8), (2026, 9), (2026, 10), (2026, 11)] {
            trades.append(buy(2, 5_000, year, month, 15))
        }
        trades.append(buy(2, 5_000, 2026, 6, 17))
        trades.append(buy(1, 9_000, 2026, 7, 15, asset: .gold(.quarter))) // başka varlık sayılmaz
        let progress = SavingsPlanMath.progress(of: plan, trades: trades, now: date(2026, 11, 27), calendar: calendar)
        #expect(progress.dueCount == 12)
        #expect(progress.keptCount == 10)
        #expect(progress.quantity == 20)
        #expect(progress.averageCost == 5_000)
        #expect(progress.nextDue == calendar.startOfDay(for: date(2026, 12, 15)))
        #expect(progress.usdAlternative(usdTRYNow: 50) == 125_000)
    }

    @Test("Vadeden 2 gün önceki alım o vadeye sayılır, bir öncekine değil")
    func earlyBuy() {
        let plan = SavingsPlanRule(asset: .gold(.gram24), target: .quantity(1),
                                   trigger: .schedule(.monthly(day: 15)), start: date(2026, 9, 1))
        let trades = [buy(1, 5_000, 2026, 10, 13)]
        let progress = SavingsPlanMath.progress(of: plan, trades: trades, now: date(2026, 10, 20), calendar: calendar)
        #expect(progress.dueCount == 2)
        #expect(progress.keptCount == 1)
    }

    @Test("Tutarlı plan: miktar satış fiyatından, adetli varlıkta aşağı yuvarlanır")
    func amountTarget() {
        let gram = SavingsPlanRule(asset: .gold(.gram24), target: .amount(5_000), trigger: .salary, start: date(2026, 1, 1))
        #expect(gram.quantity(at: 6_120) == Decimal(string: "0.81"))
        let quarter = SavingsPlanRule(asset: .gold(.quarter), target: .amount(25_000), trigger: .salary, start: date(2026, 1, 1))
        #expect(quarter.quantity(at: 10_300) == 2)
        #expect(quarter.quantity(at: 30_000) == nil)
    }

    @Test("Maaş tetikli plan vadeleri maaş günleri; kanonik metin gidiş-dönüş")
    func salaryAndCanonical() {
        let plan = SavingsPlanRule(asset: .gold(.gram24), target: .amount(5_000), trigger: .salary, start: date(2026, 9, 1))
        let progress = SavingsPlanMath.progress(of: plan, trades: [buy(1, 5_000, 2026, 10, 2)],
                                                salaryDates: [date(2026, 8, 1), date(2026, 9, 1), date(2026, 10, 1), date(2026, 11, 1)],
                                                now: date(2026, 11, 27), calendar: calendar)
        #expect(progress.dueCount == 3)
        #expect(progress.keptCount == 1)
        #expect(progress.nextDue == nil)
        #expect(SavingsPlanRule.trigger(canonical: plan.triggerCanonical) == .salary)
        #expect(SavingsPlanRule.target(canonical: plan.targetCanonical) == .amount(5_000))
        let monthly = SavingsPlanRule(asset: .gold(.gram24), target: .quantity(2), trigger: .schedule(.monthly(day: 15)), start: .now)
        #expect(SavingsPlanRule.trigger(canonical: monthly.triggerCanonical) == .schedule(.monthly(day: 15)))
    }
}
