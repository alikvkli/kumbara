import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("PortfolioStore")
struct PortfolioStoreTests {
    let container: ModelContainer
    let store: PortfolioStore
    let gram = AssetCode.gold(.gram24)

    init() throws {
        container = try KumbaraContainer.make(inMemory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        store = PortfolioStore(context: container.mainContext, calendar: calendar)
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400 + 43_200) }

    @Test("AC-P3-1 kalıcı katmandan")
    func acceptance() throws {
        try store.save(TradeDraft(asset: gram, quantity: 10, unitPrice: 5000, date: day(1)), usdTRYAtTrade: 40, now: day(10))
        try store.save(TradeDraft(asset: gram, quantity: 5, unitPrice: 5600, date: day(2)), usdTRYAtTrade: 41, now: day(10))
        let position = try #require(try store.positions().first)
        #expect(position.averageCost == 5200)
        let quote = Quote(asset: gram, bid: 5925, ask: 5990, asOf: day(10), source: .truncgil)!
        #expect(Valuation(position: position, quote: quote).unrealizedPnL == 10_875)
        #expect(try store.allTrades().first?.trade?.usdTRYAtTrade == 40)
    }

    @Test("Fazla satış kaydedilmez; elde olanı söyler")
    func oversell() throws {
        try store.save(TradeDraft(asset: gram, quantity: 3, unitPrice: 5000, date: day(1)), usdTRYAtTrade: nil, now: day(10))
        #expect(throws: PortfolioStoreError.invalid([.oversell(available: 3)])) {
            try store.save(TradeDraft(asset: gram, side: .sell, quantity: 4, unitPrice: 6000, date: day(2)),
                           usdTRYAtTrade: nil, now: day(10))
        }
    }

    @Test("Satışı geçersiz kılacak alım silinemez")
    func deleteProtectsSells() throws {
        let buy = try store.save(TradeDraft(asset: gram, quantity: 3, unitPrice: 5000, date: day(1)), usdTRYAtTrade: nil, now: day(10))
        try store.save(TradeDraft(asset: gram, side: .sell, quantity: 2, unitPrice: 6000, date: day(2)), usdTRYAtTrade: nil, now: day(10))
        #expect(throws: PortfolioError.self) { try store.delete(buy) }
        #expect(try store.allTrades().count == 2)
    }

    @Test("Düzenleme: miktar düşürülüp sonraki satış aşılırsa reddedilir")
    func editValidation() throws {
        let buy = try store.save(TradeDraft(asset: gram, quantity: 3, unitPrice: 5000, date: day(1)), usdTRYAtTrade: nil, now: day(10))
        try store.save(TradeDraft(asset: gram, side: .sell, quantity: 2, unitPrice: 6000, date: day(2)), usdTRYAtTrade: nil, now: day(10))
        var draft = try #require(buy.draft)
        draft.quantity = 1
        #expect(throws: (any Error).self) { try store.save(draft, editing: buy, usdTRYAtTrade: nil, now: day(10)) }
        draft.quantity = 5
        try store.save(draft, editing: buy, usdTRYAtTrade: nil, now: day(10))
        #expect(try store.positions().first?.quantity == 3)
    }

    @Test("Fiyat kaydı: günde bir satır, yeni fiyat eskisini ezer; son fiyatlar okunur")
    func snapshots() throws {
        let morning = Quote(asset: gram, bid: 5900, ask: 5950, asOf: day(5), source: .truncgil)!
        let evening = Quote(asset: gram, bid: 5920, ask: 5970, asOf: day(5).addingTimeInterval(3600), source: .truncgil)!
        let older = Quote(asset: gram, bid: 5800, ask: 5850, asOf: day(5).addingTimeInterval(-60), source: .truncgil)!
        try store.record([morning])
        try store.record([evening])
        try store.record([older])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PriceSnapshot>()) == 1)
        #expect(try store.latestQuotes()[gram]?.bid == 5920)

        try store.record([Quote(asset: gram, bid: 6000, ask: 6050, asOf: day(6), source: .truncgil)!])
        let history = try store.priceHistory(priceKind: .bid)[gram] ?? []
        #expect(history.map(\.price) == [5920, 6000])
    }

    @Test("Serbest varlık elle fiyatıyla değerlenir")
    func customAsset() throws {
        let fund = CustomAsset(name: "AFT Fonu")
        fund.manualPrice = Decimal(string: "1.2345")
        fund.manualPriceDate = day(4)
        container.mainContext.insert(fund)
        try container.mainContext.save()
        try store.save(TradeDraft(asset: fund.code, quantity: 1000, unitPrice: 1, date: day(1)), usdTRYAtTrade: nil, now: day(10))
        let quote = try #require(try store.latestQuotes()[fund.code])
        #expect(quote.source == .manual)
        let position = try #require(try store.positions().first)
        #expect(Valuation(position: position, quote: quote).value == Decimal(string: "1234.5"))
    }
}
