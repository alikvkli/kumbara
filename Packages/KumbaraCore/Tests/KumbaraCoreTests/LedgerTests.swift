import Foundation
import Testing
@testable import KumbaraCore

private var istanbul: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    istanbul.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func tl(_ s: String) -> Money { Money(Decimal(canonical: s)!, .TRY) }

@Suite("TransactionDraft doğrulama")
struct TransactionDraftTests {
    let cash = TransactionDraft.AccountRef(id: UUID(), currency: .TRY)
    let bank = TransactionDraft.AccountRef(id: UUID(), currency: .TRY)
    let usdAccount = TransactionDraft.AccountRef(id: UUID(), currency: .USD)
    let food = TransactionDraft.CategoryRef(id: UUID(), kind: .expense)
    let salary = TransactionDraft.CategoryRef(id: UUID(), kind: .income)

    @Test func validExpense() {
        let draft = TransactionDraft(kind: .expense, amount: 250, account: cash, category: food)
        #expect(draft.isValid)
    }

    @Test("Kategori opsiyoneldir (REQ-L4: 2 dokunuşla kayıt)")
    func categoryOptional() {
        #expect(TransactionDraft(kind: .expense, amount: 1, account: cash).isValid)
    }

    @Test func amountIssues() {
        #expect(TransactionDraft(account: cash).issues == [.missingAmount])
        #expect(TransactionDraft(amount: 0, account: cash).issues == [.nonPositiveAmount])
        #expect(TransactionDraft(amount: -5, account: cash).issues == [.nonPositiveAmount])
    }

    @Test func missingAccount() {
        #expect(TransactionDraft(amount: 5).issues == [.missingAccount])
    }

    @Test func categoryKind() {
        #expect(TransactionDraft(kind: .expense, amount: 5, account: cash, category: salary).issues == [.categoryKindMismatch])
        #expect(TransactionDraft(kind: .income, amount: 5, account: cash, category: salary).isValid)
        #expect(TransactionDraft(kind: .transfer, amount: 5, account: cash, toAccount: bank, category: food).issues == [.categoryKindMismatch])
    }

    @Test func transfer() {
        #expect(TransactionDraft(kind: .transfer, amount: 5, account: cash, toAccount: bank).isValid)
        #expect(TransactionDraft(kind: .transfer, amount: 5, account: cash).issues == [.missingDestination])
        #expect(TransactionDraft(kind: .transfer, amount: 5, account: cash, toAccount: cash).issues == [.sameAccountTransfer])
        #expect(TransactionDraft(kind: .transfer, amount: 5, account: cash, toAccount: usdAccount).issues == [.transferCurrencyMismatch])
    }

    @Test func merchantTrim() {
        #expect(TransactionDraft(merchant: "  Migros ").trimmedMerchant == "Migros")
        #expect(TransactionDraft(merchant: "   ").trimmedMerchant == nil)
    }
}

@Suite("Aylık özet (REQ-B3, B4)")
struct MonthlySummaryTests {
    let market = UUID(), fuel = UUID()
    let nov = LedgerMonth(year: 2026, month: 11)

    var entries: [LedgerEntry] {
        [
            LedgerEntry(date: date(2026, 11, 1), amount: tl("62000"), kind: .income),
            LedgerEntry(date: date(2026, 11, 3), amount: tl("1249.90"), kind: .expense, categoryID: market),
            LedgerEntry(date: date(2026, 11, 5), amount: tl("1500"), kind: .expense, categoryID: fuel),
            LedgerEntry(date: date(2026, 11, 20), amount: tl("750.10"), kind: .expense, categoryID: market),
            LedgerEntry(date: date(2026, 11, 21), amount: tl("100"), kind: .expense),
            // Hariç tutulanlar:
            LedgerEntry(date: date(2026, 11, 10), amount: tl("5000"), kind: .transfer),
            LedgerEntry(date: date(2026, 11, 11), amount: tl("999"), kind: .expense, status: .draft),
            LedgerEntry(date: date(2026, 10, 31, 23), amount: tl("300"), kind: .expense),
            LedgerEntry(date: date(2026, 12, 1, 0), amount: tl("300"), kind: .expense),
            LedgerEntry(date: date(2026, 11, 12), amount: Money(40, .USD), kind: .expense),
        ]
    }

    @Test func totals() {
        let s = MonthlySummary(entries: entries, month: nov, currency: .TRY, calendar: istanbul)
        #expect(s.income == tl("62000"))
        #expect(s.expense == tl("3600"))
        #expect(s.net == tl("58400"))
        #expect(s.entryCount == 5)
        #expect(s.otherCurrencies == [.USD])
    }

    @Test("Kategori dağılımı büyükten küçüğe, kategorisizler dahil")
    func byCategory() {
        let s = MonthlySummary(entries: entries, month: nov, currency: .TRY, calendar: istanbul)
        #expect(s.expenseByCategory.map(\.categoryID) == [market, fuel, nil])
        #expect(s.expenseByCategory.map(\.total) == [tl("2000"), tl("1500"), tl("100")])
        #expect(s.expenseByCategory.last?.share == Decimal(100) / Decimal(3600))
    }

    @Test("Ay sınırı yerel saat dilimine göre")
    func monthBoundary() {
        let oct = MonthlySummary(entries: entries, month: nov.previous, currency: .TRY, calendar: istanbul)
        #expect(oct.expense == tl("300"))
        let dec = MonthlySummary(entries: entries, month: nov.next, currency: .TRY, calendar: istanbul)
        #expect(dec.expense == tl("300"))
    }

    @Test func emptyMonth() {
        let s = MonthlySummary(entries: [], month: nov, currency: .TRY, calendar: istanbul)
        #expect(s.net == .zero(.TRY))
        #expect(s.expenseByCategory.isEmpty)
    }

    @Test func expenseChange() {
        let nov = MonthlySummary(entries: entries, month: nov, currency: .TRY, calendar: istanbul)
        let oct = MonthlySummary(entries: entries, month: self.nov.previous, currency: .TRY, calendar: istanbul)
        #expect(nov.expenseChange(from: oct) == (Decimal(3600) - 300) / 300)
        let sep = MonthlySummary(entries: [], month: self.nov.previous.previous, currency: .TRY, calendar: istanbul)
        #expect(oct.expenseChange(from: sep) == nil)
    }

    @Test func monthNavigation() {
        #expect(LedgerMonth(year: 2026, month: 1).previous == LedgerMonth(year: 2025, month: 12))
        #expect(LedgerMonth(year: 2026, month: 12).next == LedgerMonth(year: 2027, month: 1))
        #expect(LedgerMonth(containing: date(2026, 11, 30, 23), calendar: istanbul) == nov)
    }

    /// specs/06 §10 tel kafesi: 27 Kasım'da ₺18.420,50 kalan → 4 gün, günlük ₺4.605,125.
    @Test("Günlük harcanabilir")
    func dailyAllowance() throws {
        let a = try #require(DailyAllowance(remaining: tl("18420.50"), month: nov, today: date(2026, 11, 27, 9), calendar: istanbul))
        #expect(a.remainingDays == 4)
        #expect(a.perDay == tl("4605.125"))
        #expect(a.perDay.rounded() == tl("4605.13"))

        let last = try #require(DailyAllowance(remaining: tl("100"), month: nov, today: date(2026, 11, 30, 23), calendar: istanbul))
        #expect(last.remainingDays == 1)

        let negative = try #require(DailyAllowance(remaining: tl("-50"), month: nov, today: date(2026, 11, 2), calendar: istanbul))
        #expect(negative.perDay == .zero(.TRY))

        #expect(DailyAllowance(remaining: tl("100"), month: nov, today: date(2026, 12, 1), calendar: istanbul) == nil)
    }

    @Test func signedAmount() {
        #expect(LedgerEntry(date: .now, amount: tl("10"), kind: .expense).signedAmount == tl("-10"))
        #expect(LedgerEntry(date: .now, amount: tl("10"), kind: .income).signedAmount == tl("10"))
        #expect(LedgerEntry(date: .now, amount: tl("10"), kind: .transfer).signedAmount == .zero(.TRY))
    }
}

@Suite("Satıcı öğrenme (REQ-L6)")
struct MerchantTests {
    @Test("Normalizasyon", arguments: [
        ("MİGROS TİC. A.Ş.", "migros"),
        ("Migros", "migros"),
        ("  migros  ", "migros"),
        ("ŞOK MARKETLER TİC. A.Ş.", "sok marketler"),
        ("Şok", "sok"),
        ("IŞIK ECZANESİ", "isik eczanesi"),
        ("Starbucks Coffee", "starbucks coffee"),
        ("OPET PETROLCÜLÜK A.Ş.", "opet petrolculuk"),
        ("A101 Yeni Mağazacılık A.Ş.", "a101 yeni"),
        ("Trendyol.com", "trendyol com"),
        ("", ""),
        ("A.Ş.", ""),
    ])
    func normalize(raw: String, expected: String) {
        #expect(MerchantKey.normalize(raw) == expected)
    }

    @Test("Son kullanılan kategori önerilir")
    func lastUsedWins() {
        let market = UUID(), food = UUID()
        var book = MerchantRuleBook()
        book.record(merchant: "MİGROS TİC. A.Ş.", categoryID: market, at: date(2026, 11, 1))
        #expect(book.suggestedCategory(for: "Migros") == market)
        book.record(merchant: "Migros", categoryID: food, at: date(2026, 11, 2))
        #expect(book.suggestedCategory(for: "migros") == food)
        #expect(book.rules["migros"]?.useCount == 2)
        #expect(book.rules["migros"]?.displayName == "Migros")
    }

    @Test("Geçmiş tarihli kayıt yeni kuralı ezmez")
    func olderDoesNotOverride() {
        let a = UUID(), b = UUID()
        var book = MerchantRuleBook()
        book.record(merchant: "Opet", categoryID: a, at: date(2026, 11, 10))
        book.record(merchant: "Opet", categoryID: b, at: date(2026, 10, 1))
        #expect(book.suggestedCategory(for: "Opet") == a)
        #expect(book.rules["opet"]?.useCount == 2)
    }

    @Test func emptyMerchantIgnored() {
        var book = MerchantRuleBook()
        #expect(book.record(merchant: "  ", categoryID: UUID(), at: .now) == nil)
        #expect(book.rules.isEmpty)
        #expect(book.suggestedCategory(for: "x") == nil)
    }

    @Test("Otomatik tamamlama: sık kullanılan önce, kelime öneki eşleşir")
    func completions() {
        let c = UUID()
        var book = MerchantRuleBook()
        book.record(merchant: "Migros", categoryID: c, at: date(2026, 11, 1))
        book.record(merchant: "Migros", categoryID: c, at: date(2026, 11, 2))
        book.record(merchant: "Mado", categoryID: c, at: date(2026, 11, 3))
        book.record(merchant: "Şok Market", categoryID: c, at: date(2026, 11, 2))
        #expect(book.completions(for: "m").map(\.displayName) == ["Migros", "Mado", "Şok Market"])
        #expect(book.completions(for: "Mİ").map(\.displayName) == ["Migros"])
        #expect(book.completions(for: "şo").map(\.displayName) == ["Şok Market"])
        #expect(book.completions(for: "").isEmpty)
        #expect(book.completions(for: "m", limit: 1).count == 1)
    }
}

@Suite("Varsayılan kategoriler (REQ-L5)")
struct DefaultCategoriesTests {
    @Test("Anahtarlar benzersiz")
    func uniqueKeys() {
        let keys = DefaultCategories.allKeys
        #expect(Set(keys).count == keys.count)
    }

    @Test("Alt kategoriler üstüyle aynı türde, iki seviyeden derin değil")
    func structure() {
        for parent in DefaultCategories.all {
            #expect(parent.symbol != nil)
            for child in parent.children {
                #expect(child.kind == parent.kind)
                #expect(child.children.isEmpty)
            }
        }
        #expect(DefaultCategories.expense.allSatisfy { $0.kind == .expense })
        #expect(DefaultCategories.income.allSatisfy { $0.kind == .income })
    }

    @Test func localizedName() {
        let market = DefaultCategories.expense[0]
        #expect(market.name(for: Locale(identifier: "tr_TR")) == "Market")
        #expect(market.name(for: Locale(identifier: "en_US")) == "Groceries")
    }
}
