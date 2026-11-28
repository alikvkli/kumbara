import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("Kira sözleşmeleri (specs/12)")
struct RentStoreTests {
    private let containers = ContainerBag()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))! }

    private func demoContext() throws -> ModelContext {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        try DemoData.load(into: context, now: now, calendar: calendar)
        return context
    }

    @Test("Örnek veri: 1 Kasım'da yenilenen ₺22.500 kira, Ekim oranıyla; yeni kira kurala yazılır (AC-I9-4)")
    func demoContractAndApply() throws {
        let context = try demoContext()
        let store = RentStore(context: context)
        let contract = try #require(try store.contracts().first)
        let quote = store.quote(for: contract, now: now, calendar: calendar)
        #expect(quote.year == 3)
        #expect(quote.referenceMonth == LedgerMonth(year: 2026, month: 10))
        let rate = try #require(RentIncrease.averageChange(for: LedgerMonth(year: 2026, month: 10), cpi: CPIData.turkey))
        #expect(quote.rate == rate)
        #expect(quote.maximumRent == (22_500 * (1 + rate)).rounded(scale: 2))

        let rule = try #require(try store.linkedRule(of: contract))
        #expect(rule.category?.seedKey == "housing.rent")
        try store.applyNewRent(29_000, to: contract)
        #expect(contract.rent == 29_000)
        #expect(rule.amount == 29_000)
        #expect(try store.candidateRules().first?.category?.seedKey == "housing.rent")
    }

    @Test("Elle oran saklanır; yedekten aynen döner")
    func manualRateAndBackup() throws {
        let context = try demoContext()
        let store = RentStore(context: context)
        let start = calendar.date(from: DateComponents(year: 2025, month: 12, day: 15))!
        let shop = try store.add(name: "Dükkân", role: .landlord, start: start, rent: 40_000, calendar: calendar)
        let missing = store.quote(for: shop, now: now, calendar: calendar)
        #expect(missing.referenceMonth == LedgerMonth(year: 2026, month: 11))
        #expect(missing.rate == nil)
        try store.setManualRate(Decimal(string: "0.31"), month: missing.referenceMonth, for: shop)
        #expect(store.quote(for: shop, now: now, calendar: calendar).maximumRent == 52_400)

        let data = try ExchangeStore(context: context).backupJSON(now: now)
        let target = try containers.make()
        try LedgerSeeder.seedIfNeeded(target, locale: Locale(identifier: "tr_TR"))
        try ExchangeStore(context: target).restore(data, mode: .replace)
        let restored = try RentStore(context: target).contracts()
        #expect(restored.count == 2)
        let copy = try #require(restored.first { $0.id == shop.id })
        #expect(copy.role == .landlord)
        #expect(copy.rent == 40_000)
        #expect(copy.manualRate?.rate == Decimal(string: "0.31"))
        #expect(RentStore(context: target).quote(for: copy, now: now, calendar: calendar).maximumRent == 52_400)

        // Birleştirmede çift kayıt yok.
        try ExchangeStore(context: target).restore(data, mode: .merge)
        #expect(try RentStore(context: target).contracts().count == 2)
    }
}
