import Foundation
import Testing
@testable import KumbaraCore

@Suite("Bütçeler (specs/08 §1)")
struct BudgetTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()
    let market = UUID(), food = UUID(), household = UUID(), cafe = UUID(), salary = UUID()
    var index: CategoryIndex {
        CategoryIndex(parent: [food: market, household: market], expense: [market, food, household, cafe])
    }
    let november = LedgerMonth(year: 2026, month: 11)

    func day(_ d: Int, month: Int = 11) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: 12))! }
    func expense(_ amount: String, _ category: UUID?, day d: Int = 10, currency: CurrencyCode = .TRY) -> LedgerEntry {
        LedgerEntry(date: day(d), amount: Money(Decimal(canonical: amount)!, currency), kind: .expense, categoryID: category)
    }
    func history(_ limit: Decimal, from month: LedgerMonth? = nil) -> BudgetLimitHistory {
        var h = BudgetLimitHistory()
        h.set(limit, from: month ?? november)
        return h
    }

    @Test("AC-B1-1: üst kategori bütçesi alt kategorileri içerir; %82,5 uyarı seviyesi")
    func rollUp() {
        let budget = BudgetSpec(categoryID: market, history: history(4000))
        let entries = [expense("2500", food), expense("800", household), expense("300", cafe)]
        let status = BudgetMath.statuses([budget], entries: entries, categories: index, month: november,
                                         today: day(20), calendar: calendar)[0]
        #expect(status.spent.amount == 3300)
        #expect(status.ratio == Decimal(string: "0.825"))
        #expect(status.level == .warning)
        #expect(BudgetMath.reachedThresholds(status) == [80])
    }

    @Test("Genel bütçe: kategorisizler dahil tüm giderler, iade düşer, transfer ve taslak sayılmaz")
    func overall() {
        let budget = BudgetSpec(categoryID: nil, history: history(10_000))
        var draft = expense("999", food)
        draft.status = .draft
        let transfer = LedgerEntry(date: day(5), amount: Money(5000, .TRY), kind: .transfer)
        let refund = LedgerEntry(date: day(12), amount: Money(200, .TRY), kind: .income, categoryID: food)
        let pay = LedgerEntry(date: day(1), amount: Money(50_000, .TRY), kind: .income, categoryID: salary)
        let entries = [expense("1000", food), expense("500", nil), draft, transfer, refund, pay,
                       expense("700", food, day: 2, currency: .TRY)]
        let status = BudgetMath.statuses([budget], entries: entries, categories: index, month: november,
                                         today: day(15), calendar: calendar)[0]
        #expect(status.spent.amount == 2000) // 1000 + 500 + 700 − 200
    }

    @Test("Döviz gideri işlem günü kuruyla; kur yoksa işaretlenir")
    func currency() {
        let budget = BudgetSpec(categoryID: cafe, history: history(1000))
        let entries = [expense("10", cafe, currency: .USD), expense("5", cafe, currency: .EUR)]
        let status = BudgetMath.statuses([budget], entries: entries, categories: index, month: november, today: day(15),
                                         calendar: calendar, rate: { code, _ in code == .USD ? Decimal(string: "42.5") : nil })[0]
        #expect(status.spent.amount == 425)
        #expect(status.hasUnconvertedEntries)
    }

    @Test("Limit geçmişi: değişiklik o aydan itibaren, geçmiş korunur; kanonik metin gidip gelir")
    func limitHistory() throws {
        var h = BudgetLimitHistory()
        h.set(4000, from: november)
        h.set(4500, from: LedgerMonth(year: 2027, month: 1))
        #expect(h.limit(for: LedgerMonth(year: 2026, month: 10)) == nil)
        #expect(h.limit(for: november) == 4000)
        #expect(h.limit(for: LedgerMonth(year: 2026, month: 12)) == 4000)
        #expect(h.limit(for: LedgerMonth(year: 2027, month: 3)) == 4500)
        #expect(h.canonical == "2026-11=4000;2027-01=4500")
        #expect(try #require(BudgetLimitHistory(canonical: h.canonical)) == h)
        #expect(BudgetLimitHistory(canonical: "2026-13=5") == nil)
        // Başlamadan önceki ayda bütçe görünmez.
        let early = BudgetMath.statuses([BudgetSpec(categoryID: cafe, history: h)], entries: [], categories: index,
                                        month: LedgerMonth(year: 2026, month: 10), today: day(1), calendar: calendar)
        #expect(early.isEmpty)
    }

    @Test("Tempo: ayın %40'ında bütçenin %62'si → hızlı gidiyor")
    func pace() {
        let budget = BudgetSpec(categoryID: cafe, history: history(1000))
        let status = BudgetMath.statuses([budget], entries: [expense("620", cafe)], categories: index, month: november,
                                         today: day(12), calendar: calendar)[0]
        #expect(status.elapsed == Decimal(12) / 30)
        #expect(status.isAheadOfPace)
        let calm = BudgetMath.statuses([budget], entries: [expense("300", cafe)], categories: index, month: november,
                                       today: day(12), calendar: calendar)[0]
        #expect(!calm.isAheadOfPace)
    }

    @Test("Eşikler: %100'de iki eşik de ulaşılmış")
    func thresholds() {
        let budget = BudgetSpec(categoryID: cafe, history: history(1000))
        let status = BudgetMath.statuses([budget], entries: [expense("1000", cafe)], categories: index, month: november,
                                         today: day(28), calendar: calendar)[0]
        #expect(status.level == .over)
        #expect(BudgetMath.reachedThresholds(status) == [80, 100])
    }

    @Test("Önerilen limit: ortalama, yukarı yuvarlanır; veri yoksa yok")
    func suggestion() {
        #expect(BudgetMath.suggestedLimit(monthlySpending: [3870, 3950, 3880]) == 3900)
        #expect(BudgetMath.suggestedLimit(monthlySpending: [612, 0, 640]) == 650)
        #expect(BudgetMath.suggestedLimit(monthlySpending: [18_200, 17_900]) == 18_500)
        #expect(BudgetMath.suggestedLimit(monthlySpending: [0, 0]) == nil)
    }

    @Test("Tempo, ay sonu tahmini, günlük hak: ayın 12'si, ₺1.000 bütçenin ₺620'si gitti")
    func paceProjection() {
        let budget = BudgetSpec(categoryID: cafe, history: history(1000))
        let status = BudgetMath.statuses([budget], entries: [expense("620", cafe)], categories: index, month: november,
                                         today: day(12), calendar: calendar)[0]
        #expect(status.remainingDays == 19)                         // 12 dahil 30'a kadar
        #expect(status.expected.amount == 400)                      // 1000 × 12/30
        #expect(status.paceDelta.amount == 220)                     // plandan ₺220 ileride
        #expect(status.projected?.amount == 1550)                   // 620 / 0,4
        #expect(status.isProjectedOver)
        #expect(status.perDay.amount == Decimal(string: "20")!)     // 380 / 19
        // Ayın başında tahmin yok (gürültü).
        let early = BudgetMath.statuses([budget], entries: [expense("100", cafe, day: 1)], categories: index, month: november,
                                        today: day(2), calendar: calendar)[0]
        #expect(early.projected == nil)
        // Geçmiş ay: kalan gün 0, günlük hak 0, tahmin = gerçekleşen.
        let past = BudgetMath.statuses([budget], entries: [expense("620", cafe)], categories: index, month: november,
                                       today: day(5, month: 12), calendar: calendar)[0]
        #expect(past.remainingDays == 0 && past.perDay.isZero && past.projected?.amount == 620)
    }

    @Test("Günlük birikimli seri: grafik için, bugüne kadar")
    func cumulative() {
        let budget = BudgetSpec(categoryID: market, history: history(4000))
        let entries = [expense("100", food, day: 2), expense("50", household, day: 2), expense("300", food, day: 5),
                       expense("999", cafe, day: 3)]
        let series = BudgetMath.dailyCumulative(budget, entries: entries, categories: index, month: november,
                                                through: day(6), calendar: calendar)
        #expect(series.map(\.day) == [1, 2, 3, 4, 5, 6])
        #expect(series.map(\.total) == [0, 150, 150, 150, 450, 450])
    }
}
