import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("LedgerStore")
struct LedgerStoreTests {
    let container: ModelContainer
    let store: LedgerStore
    let tr = Locale(identifier: "tr_TR")

    init() throws {
        container = try KumbaraContainer.make(inMemory: true)
        store = LedgerStore(context: container.mainContext)
        try LedgerSeeder.seedIfNeeded(container.mainContext, locale: tr)
    }

    private func category(_ key: String) throws -> LedgerCategory {
        try #require(try container.mainContext.fetch(FetchDescriptor<LedgerCategory>()).first { $0.seedKey == key })
    }

    @Test("Seed: tüm varsayılan kategoriler + Nakit hesabı; tekrar çağrı çoğaltmaz")
    func seeding() throws {
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<LedgerCategory>()) == DefaultCategories.allKeys.count)
        try LedgerSeeder.seedIfNeeded(context, locale: tr)
        #expect(try context.fetchCount(FetchDescriptor<LedgerCategory>()) == DefaultCategories.allKeys.count)
        let accounts = try store.activeAccounts()
        #expect(accounts.map(\.name) == ["Nakit"])
        #expect(accounts.first?.currency == .TRY)
        #expect(try category("market.food").parent?.seedKey == "market")
        #expect(try category("market.food").resolvedSymbol == "cart")
        #expect(try category("market.food").path == "Market › Gıda")
    }

    @Test("Kaydet → oku: tutar Decimal hassasiyetinde, satıcı normalize")
    func saveAndRead() throws {
        let cash = try #require(try store.defaultAccount())
        let market = try category("market")
        let draft = TransactionDraft(kind: .expense, amount: Decimal(canonical: "1249.90"), date: .now,
                                     account: cash.ref, category: market.ref, merchant: "  MİGROS TİC. A.Ş. ")
        let saved = try store.save(draft)
        #expect(saved.amount == Money(Decimal(canonical: "1249.9")!, .TRY))
        #expect(saved.merchant == "MİGROS TİC. A.Ş.")
        #expect(saved.merchantKey == "migros")
        #expect(saved.signedAmount == Money(Decimal(canonical: "-1249.9")!, .TRY))
        #expect(cash.balance == Money(Decimal(canonical: "-1249.9")!, .TRY))
    }

    @Test("Geçersiz taslak reddedilir")
    func invalid() throws {
        #expect(throws: LedgerStoreError.invalid([.missingAmount, .missingAccount])) {
            try store.save(TransactionDraft())
        }
        let ghost = TransactionDraft.AccountRef(id: UUID(), currency: .TRY)
        #expect(throws: LedgerStoreError.accountNotFound) {
            try store.save(TransactionDraft(amount: 5, account: ghost))
        }
    }

    @Test("Satıcı hafızası: ikinci girişte kategori önerilir (REQ-L6)")
    func merchantLearning() throws {
        let cash = try #require(try store.defaultAccount())
        let market = try category("market"), food = try category("market.food")
        #expect(try store.suggestedCategory(forMerchant: "Migros") == nil)

        try store.save(TransactionDraft(amount: 10, date: Date(timeIntervalSince1970: 1_000), account: cash.ref,
                                        category: market.ref, merchant: "MİGROS"))
        #expect(try store.suggestedCategory(forMerchant: "migros")?.id == market.id)

        try store.save(TransactionDraft(amount: 10, date: Date(timeIntervalSince1970: 2_000), account: cash.ref,
                                        category: food.ref, merchant: "Migros"))
        #expect(try store.suggestedCategory(forMerchant: "Migros")?.id == food.id)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MerchantMemory>()) == 1)
        #expect(try store.merchantCompletions(for: "mi").map(\.displayName) == ["Migros"])
    }

    @Test("Düzenleme aynı kaydı günceller")
    func edit() throws {
        let cash = try #require(try store.defaultAccount())
        let saved = try store.save(TransactionDraft(amount: 10, account: cash.ref, merchant: "Opet"))
        var draft = saved.draft
        draft.amount = 25
        draft.kind = .income
        try store.save(draft, editing: saved)
        let all = try container.mainContext.fetch(FetchDescriptor<LedgerTransaction>())
        #expect(all.count == 1)
        #expect(all.first?.amount == Money(25, .TRY))
        #expect(all.first?.kind == .income)
    }

    @Test("Transfer: iki hesap, toplamlara girmez, bakiyeler doğru")
    func transfer() throws {
        let cash = try #require(try store.defaultAccount())
        let bank = LedgerAccount(name: "Banka", kind: .bank, currency: .TRY, openingBalance: 10_000, sortIndex: 1)
        container.mainContext.insert(bank)
        try container.mainContext.save()

        try store.save(TransactionDraft(kind: .transfer, amount: 2_000, account: bank.ref, toAccount: cash.ref,
                                        merchant: "yok sayılır"))
        #expect(bank.balance == Money(8_000, .TRY))
        #expect(cash.balance == Money(2_000, .TRY))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let summary = try store.summary(for: LedgerMonth(containing: .now, calendar: calendar),
                                        currency: .TRY, calendar: calendar)
        #expect(summary.expense == .zero(.TRY))
        #expect(summary.income == .zero(.TRY))
        let transfer = try #require(try container.mainContext.fetch(FetchDescriptor<LedgerTransaction>()).first)
        #expect(transfer.merchant == nil)
    }

    @Test("Ön seçili hesap son kullanılan hesaptır")
    func defaultAccount() throws {
        let bank = LedgerAccount(name: "Banka", kind: .bank, currency: .TRY, sortIndex: 1)
        container.mainContext.insert(bank)
        try container.mainContext.save()
        #expect(try store.defaultAccount()?.name == "Nakit")
        try store.save(TransactionDraft(amount: 5, account: bank.ref))
        #expect(try store.defaultAccount()?.name == "Banka")
    }

    @Test func recentCategories() throws {
        let cash = try #require(try store.defaultAccount())
        let market = try category("market"), fuel = try category("transport.fuel"), salary = try category("salary")
        try store.save(TransactionDraft(amount: 1, date: Date(timeIntervalSince1970: 1), account: cash.ref, category: market.ref))
        try store.save(TransactionDraft(amount: 1, date: Date(timeIntervalSince1970: 2), account: cash.ref, category: fuel.ref))
        try store.save(TransactionDraft(amount: 1, date: Date(timeIntervalSince1970: 3), account: cash.ref, category: market.ref))
        try store.save(TransactionDraft(kind: .income, amount: 1, date: Date(timeIntervalSince1970: 4), account: cash.ref, category: salary.ref))
        #expect(try store.recentCategories(kind: .expense).map(\.seedKey) == ["market", "transport.fuel"])
        #expect(try store.recentCategories(kind: .income).map(\.seedKey) == ["salary"])
    }
}

@MainActor
@Suite("Örnek veri")
struct DemoDataTests {
    @Test("Örnek veri geçerli kayıtlar üretir ve gelecek tarih eklemez")
    func loads() throws {
        let container = try KumbaraContainer.make(inMemory: true)
        let context = container.mainContext
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))!
        try DemoData.load(into: context, now: now, calendar: calendar)

        let all = try context.fetch(FetchDescriptor<LedgerTransaction>())
        #expect(all.count == 23)
        #expect(all.allSatisfy { $0.date <= now })
        let summary = try LedgerStore(context: context).summary(
            for: LedgerMonth(year: 2026, month: 11), currency: .TRY, calendar: calendar)
        #expect(summary.income == Money(69_500, .TRY))
        #expect(summary.expense == Money(Decimal(canonical: "35805.69")!, .TRY))
        #expect(try LedgerStore(context: context).suggestedCategory(forMerchant: "migros")?.seedKey == "market.food")

        let portfolio = PortfolioStore(context: context, calendar: calendar)
        #expect(try portfolio.allTrades().count == 7)
        #expect(try portfolio.heldAssets().count == 4)
        #expect(try portfolio.positions().first { $0.asset == .gold(.gram24) }?.quantity == Decimal(string: "17.5"))
        #expect(try context.fetchCount(FetchDescriptor<PriceSnapshot>()) == 210 * 3)
    }
}
