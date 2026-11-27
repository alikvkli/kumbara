import Foundation
import Testing
@testable import KumbaraCore

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

@Suite("Abonelikler (specs/10 §2)")
struct SubscriptionTests {
    private func pay(_ name: String, _ amount: Decimal, _ year: Int, _ month: Int, _ day: Int,
                     recurring: Bool = false) -> SubscriptionDetector.Payment {
        .init(date: date(year, month, day), amount: amount, merchantKey: MerchantKey.normalize(name),
              merchantName: name, isRecurring: recurring)
    }

    @Test("3 ay ₺229, 4. ay ₺279 → abonelik, +%22 artış (AC-I2-1)")
    func priceIncrease() throws {
        let payments = [
            pay("Netflix", 229, 2026, 8, 9), pay("Netflix", 229, 2026, 9, 9),
            pay("Netflix", 229, 2026, 10, 9), pay("Netflix", 279, 2026, 11, 9),
        ]
        let found = SubscriptionDetector.detect(payments, now: date(2026, 11, 27), calendar: calendar)
        let netflix = try #require(found.first)
        #expect(found.count == 1)
        #expect(netflix.cadence == .monthly)
        #expect(netflix.payments.count == 4)
        #expect(netflix.previousAmount == 229)
        let increase = try #require(netflix.priceIncrease)
        #expect(abs(increase - 0.2183) < 0.001)
        #expect(netflix.nextDue == date(2026, 12, 9))
        #expect(!netflix.isMissed)
    }

    @Test("İki ödemeli satıcı abonelik sayılmaz (AC-I2-1)")
    func needsThree() {
        let payments = [pay("Spotify", 99, 2026, 10, 3), pay("Spotify", 99, 2026, 11, 3)]
        #expect(SubscriptionDetector.detect(payments, now: date(2026, 11, 27), calendar: calendar).isEmpty)
    }

    @Test("Haftalık market alışverişi abonelik değil")
    func weeklyIsNot() {
        let payments = (0..<10).map { pay("Migros", 800, 2026, 9, 1 + $0 * 3) }
        #expect(SubscriptionDetector.detect(payments, now: date(2026, 9, 30), calendar: calendar).isEmpty)
    }

    @Test("Tutar çok oynayan ödeme abonelik değil")
    func volatileAmount() {
        let payments = [pay("Enerjisa", 400, 2026, 8, 5), pay("Enerjisa", 900, 2026, 9, 5),
                        pay("Enerjisa", 300, 2026, 10, 5)]
        #expect(SubscriptionDetector.detect(payments, now: date(2026, 10, 20), calendar: calendar).isEmpty)
    }

    @Test("Tekrarlayan kuraldan gelen ödeme 'tanımlı' olarak işaretlenir (AC-I2-2)")
    func tracked() throws {
        let payments = [pay("Kira", 18_000, 2026, 9, 1, recurring: true), pay("Kira", 18_000, 2026, 10, 1, recurring: true),
                        pay("Kira", 18_000, 2026, 11, 1, recurring: true)]
        let found = try #require(SubscriptionDetector.detect(payments, now: date(2026, 11, 20), calendar: calendar).first)
        #expect(found.isTracked)
        #expect(found.previousAmount == nil)
    }

    @Test("Beklenen günden 10 gün geçti → 'görünmedi'; 40 günü geçti → listelenmez")
    func missedAndStale() {
        let payments = [pay("Spor Salonu", 1_200, 2026, 7, 2), pay("Spor Salonu", 1_200, 2026, 8, 2),
                        pay("Spor Salonu", 1_200, 2026, 9, 2)]
        let missed = SubscriptionDetector.detect(payments, now: date(2026, 10, 20), calendar: calendar)
        #expect(missed.first?.isMissed == true)
        #expect(SubscriptionDetector.monthlyTotal(missed) == 0)
        #expect(SubscriptionDetector.detect(payments, now: date(2026, 11, 20), calendar: calendar).isEmpty)
    }

    @Test("Yıllık abonelik aylığa bölünür; reddedilen satıcı listelenmez")
    func yearlyAndDismissed() throws {
        let payments = [pay("iCloud", 1_200, 2024, 3, 10), pay("iCloud", 1_200, 2025, 3, 10),
                        pay("iCloud", 1_320, 2026, 3, 11), pay("Netflix", 229, 2026, 9, 9),
                        pay("Netflix", 229, 2026, 10, 9), pay("Netflix", 229, 2026, 11, 9)]
        let found = SubscriptionDetector.detect(payments, now: date(2026, 11, 20), calendar: calendar)
        let icloud = try #require(found.first { $0.merchantKey == "icloud" })
        #expect(icloud.cadence == .yearly)
        #expect(icloud.monthlyCost == 110)
        #expect(SubscriptionDetector.monthlyTotal(found) == 339)
        let dismissed = SubscriptionDetector.detect(payments, now: date(2026, 11, 20), calendar: calendar,
                                                    dismissedKeys: ["netflix"])
        #expect(dismissed.map(\.merchantKey) == ["icloud"])
    }
}

@Suite("Aylık rapor (specs/10 §1)")
struct MonthlyReportTests {
    private let market = UUID()
    private let fuel = UUID()
    private let rent = UUID()

    private func expense(_ amount: Decimal, _ category: UUID, _ year: Int, _ month: Int, _ day: Int,
                         merchant: String? = nil) -> LedgerEntry {
        LedgerEntry(date: date(year, month, day), amount: Money(amount, .TRY), kind: .expense,
                    categoryID: category, merchant: merchant)
    }

    private func income(_ amount: Decimal, _ year: Int, _ month: Int) -> LedgerEntry {
        LedgerEntry(date: date(year, month, 1), amount: Money(amount, .TRY), kind: .income)
    }

    @Test("Ekim ₺36.350 → Kasım ₺37.806: %4 fazla, artış markette (AC-I1-1)")
    func changeAndDriver() throws {
        let entries = [
            income(60_000, 2026, 10), income(60_000, 2026, 11),
            expense(18_000, rent, 2026, 10, 1), expense(10_000, market, 2026, 10, 5), expense(8_350, fuel, 2026, 10, 9),
            expense(18_000, rent, 2026, 11, 1), expense(11_806, market, 2026, 11, 5, merchant: "Migros"),
            expense(8_000, fuel, 2026, 11, 9),
        ]
        let report = MonthlyReport(entries: entries, month: LedgerMonth(year: 2026, month: 11), calendar: calendar)
        #expect(report.expense == 37_806)
        let change = try #require(report.change)
        #expect(abs(change - 0.04) < 0.001)
        // Akaryakıt farkı ₺350 < ₺500: listede yok.
        #expect(report.categoryChanges.map(\.categoryID) == [market])
        guard case let .changed(_, _, driver) = report.headline else {
            Issue.record("Başlık 'changed' olmalı: \(report.headline)")
            return
        }
        #expect(driver?.categoryID == market)
        #expect(report.topExpenses.first?.amount.amount == 18_000)
        #expect(report.topMerchant == nil) // tek ziyaret sayılmaz
    }

    @Test("Önceki ay yoksa 'steady', fark listesi boş; gider geliri geçerse 'overspent'")
    func headlines() {
        let first = MonthlyReport(entries: [income(10_000, 2026, 11), expense(4_000, market, 2026, 11, 3)],
                                  month: LedgerMonth(year: 2026, month: 11), calendar: calendar)
        #expect(first.headline == .steady(expense: 4_000, hasPrevious: false))
        #expect(first.categoryChanges.isEmpty)
        #expect(first.averageExpense == nil)

        let over = MonthlyReport(entries: [income(10_000, 2026, 11), expense(12_500, market, 2026, 11, 3)],
                                 month: LedgerMonth(year: 2026, month: 11), calendar: calendar)
        #expect(over.headline == .overspent(by: 2_500))
    }

    @Test("Üç ay ortalaması yalnız gideri olan aylardan; en sık satıcı en az 2 ziyaretle")
    func averageAndMerchant() throws {
        let entries = [
            income(10_000, 2026, 8), income(10_000, 2026, 10),
            expense(3_000, market, 2026, 8, 3), expense(5_000, market, 2026, 10, 3),
            // Eylül: tek abonelik, gelir yok → ortalamaya girmez.
            expense(99, market, 2026, 9, 12),
            expense(400, market, 2026, 11, 2, merchant: "Kahve Dünyası"),
            expense(200, market, 2026, 11, 9, merchant: "KAHVE DÜNYASI"),
            expense(5_000, market, 2026, 11, 12, merchant: "Migros"),
        ]
        let report = MonthlyReport(entries: entries, month: LedgerMonth(year: 2026, month: 11), calendar: calendar)
        #expect(report.averageMonths == 2)
        #expect(report.averageExpense == 4_000)
        let visit = try #require(report.topMerchant)
        #expect(visit.count == 2)
        #expect(visit.total == 600)
    }

    @Test("Bütçe satırları: genel bütçe ve aşan kategoriler")
    func budgets() {
        let lines = [MonthlyReport.BudgetLine(categoryID: nil, limit: 40_000, spent: 36_800),
                     .init(categoryID: market, limit: 10_000, spent: 11_800),
                     .init(categoryID: fuel, limit: 9_000, spent: 8_000)]
        let report = MonthlyReport(entries: [expense(36_800, market, 2026, 11, 2)],
                                   month: LedgerMonth(year: 2026, month: 11), calendar: calendar, budgets: lines)
        #expect(report.budget?.usage == Decimal(string: "0.92"))
        #expect(report.overBudget.map(\.categoryID) == [market])
        #expect(report.overBudget.first?.overrun == 1_800)
    }

    @Test("Birikim: eklenen para ve fiyat etkisi ayrılır")
    func savings() throws {
        let gram = AssetCode.gold(.gram24)
        let trades = [
            Trade(asset: gram, side: .buy, quantity: 10, unitPrice: 5_000, date: date(2026, 9, 1)),
            Trade(asset: gram, side: .buy, quantity: 2, unitPrice: 5_500, date: date(2026, 11, 10)),
        ]
        let prices: [AssetCode: [(date: Date, price: Decimal)]] = [gram: [
            (calendar.startOfDay(for: date(2026, 10, 31)), 5_400),
            (calendar.startOfDay(for: date(2026, 11, 30)), 5_700),
        ]]
        let cpi = RealReturn.CPITable([LedgerMonth(year: 2026, month: 10): 100, LedgerMonth(year: 2026, month: 11): 102])
        let savings = try #require(MonthlyReport.Savings.compute(
            trades: trades, prices: prices, month: LedgerMonth(year: 2026, month: 11),
            now: date(2026, 12, 1), calendar: calendar, cpi: cpi))
        #expect(savings.startValue == 54_000)
        #expect(savings.endValue == 68_400)
        #expect(savings.contributions == 11_000)
        #expect(savings.priceEffect == 3_400)
        #expect(savings.inflation == Decimal(string: "0.02"))
    }
}
