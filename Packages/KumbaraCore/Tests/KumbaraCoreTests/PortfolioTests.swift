import Foundation
import Testing
@testable import KumbaraCore

private func d(_ s: String) -> Decimal { Decimal(canonical: s)! }
private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }
private let gram = AssetCode.gold(.gram24)

private func buy(_ q: String, _ p: String, fee: String = "0", on n: Int, usd: String? = nil) -> Trade {
    Trade(asset: gram, side: .buy, quantity: d(q), unitPrice: d(p), fee: d(fee), date: day(n), usdTRYAtTrade: usd.map(d))
}

private func sell(_ q: String, _ p: String, fee: String = "0", on n: Int) -> Trade {
    Trade(asset: gram, side: .sell, quantity: d(q), unitPrice: d(p), fee: d(fee), date: day(n))
}

private func quote(bid: String, ask: String) -> Quote {
    Quote(asset: gram, bid: d(bid), ask: d(ask), asOf: day(100), source: .truncgil)!
}

/// specs/03 §7 test vektörleri.
@Suite("Portföy matematiği (specs/03)")
struct PortfolioMathTests {
    @Test func singleBuy() throws {
        let p = try Position(asset: gram, trades: [buy("10", "5000", on: 1)])
        #expect(p.quantity == 10)
        #expect(p.costBasis == 50_000)
        #expect(p.averageCost == 5000)
        #expect(p.realizedPnL == 0)
    }

    /// specs/01 AC-P3-1
    @Test("AC-P3-1: iki alım, bozdurma fiyatıyla değer")
    func acceptance() throws {
        let p = try Position(asset: gram, trades: [buy("10", "5000", on: 1), buy("5", "5600", on: 2)])
        #expect(p.averageCost == 5200)
        #expect(p.costBasis == 78_000)
        let v = Valuation(position: p, quote: quote(bid: "5925", ask: "5990"))
        #expect(v.priceKind == .bid)
        #expect(v.value == 88_875)
        #expect(v.unrealizedPnL == 10_875)
        #expect(v.unrealizedReturn?.rounded(scale: 4) == d("0.1394"))
        #expect(v.spreadCost == Decimal(15 * 65))
    }

    @Test("Fiyat tipi: satış ve orta fiyat seçilebilir (REQ-P4)")
    func priceKinds() throws {
        let p = try Position(asset: gram, trades: [buy("2", "5000", on: 1)])
        let q = quote(bid: "5900", ask: "6000")
        #expect(Valuation(position: p, quote: q, priceKind: .ask).value == 12_000)
        #expect(Valuation(position: p, quote: q, priceKind: .mid).value == 11_900)
    }

    @Test("Ücretli alım maliyete eklenir")
    func feeOnBuy() throws {
        let p = try Position(asset: gram, trades: [buy("10", "5000", fee: "250", on: 1)])
        #expect(p.costBasis == 50_250)
        #expect(p.averageCost == 5025)
    }

    @Test("Kısmi satış: ortalama değişmez, gerçekleşen kâr hesaplanır (REQ-P6)")
    func partialSell() throws {
        let p = try Position(asset: gram, trades: [
            buy("10", "5000", on: 1), buy("5", "5600", on: 2), sell("6", "6000", fee: "120", on: 3),
        ])
        #expect(p.quantity == 9)
        #expect(p.averageCost == 5200)
        #expect(p.costBasis == 46_800)
        #expect(p.realizedPnL == Decimal(6 * (6000 - 5200) - 120))
    }

    @Test("Tam satış pozisyonu kapatır")
    func fullSell() throws {
        let p = try Position(asset: gram, trades: [buy("3", "5000", on: 1), sell("3", "5500", on: 2)])
        #expect(!p.isOpen)
        #expect(p.costBasis == 0)
        #expect(p.averageCost == nil)
        #expect(p.realizedPnL == 1500)
    }

    @Test("Fazla satış reddedilir")
    func oversell() throws {
        let s = sell("4", "5500", on: 2)
        #expect(throws: PortfolioError.oversell(tradeID: s.id, available: 3, requested: 4)) {
            try Position(asset: gram, trades: [buy("3", "5000", on: 1), s])
        }
    }

    @Test("Tarih sırası: geriye tarihli alım önce uygulanır")
    func ordering() throws {
        // Satış 3. gün, alım 1. gün ama listede sonra
        let p = try Position(asset: gram, trades: [sell("1", "6000", on: 3), buy("2", "5000", on: 1)])
        #expect(p.quantity == 1)
        #expect(p.realizedPnL == 1000)
    }

    @Test("FIFO ortalamadan farklı sonuç verir")
    func fifoDiffers() throws {
        let trades = [buy("10", "5000", on: 1), buy("10", "6000", on: 2), sell("10", "6500", on: 3)]
        let average = try Position(asset: gram, trades: trades, method: .averageCost)
        let fifo = try Position(asset: gram, trades: trades, method: .fifo)
        #expect(average.realizedPnL == Decimal(10 * (6500 - 5500)))
        #expect(fifo.realizedPnL == Decimal(10 * (6500 - 5000)))
        #expect(average.costBasis == 55_000)
        #expect(fifo.costBasis == 60_000)
        #expect(fifo.lots.count == 1)
        #expect(fifo.lots.first?.unitCost == 6000)
    }

    @Test("FIFO lotları bölerek tüketir, ücret birim maliyete dağılır")
    func fifoSplit() throws {
        let p = try Position(asset: gram, trades: [
            buy("2", "5000", fee: "100", on: 1), buy("3", "5500", on: 2), sell("3", "6000", on: 3),
        ], method: .fifo)
        // 2 × 5050 + 1 × 5500 = 15.600 maliyet; gelir 18.000
        #expect(p.realizedPnL == 2400)
        #expect(p.quantity == 2)
        #expect(p.costBasis == 11_000)
    }

    @Test("Geçersiz işlemler")
    func invalid() {
        let zero = buy("0", "5000", on: 1)
        #expect(throws: PortfolioError.invalidTrade(tradeID: zero.id)) { try Position(asset: gram, trades: [zero]) }
        let other = Trade(asset: .fx(.USD), side: .buy, quantity: 1, unitPrice: 50, date: day(1))
        #expect(throws: PortfolioError.mixedAssets) { try Position(asset: gram, trades: [other]) }
    }

    @Test("Reel getiri: USD karşılaştırması (specs/03 §4)")
    func usdBenchmark() throws {
        // 100.000 TL @ 40 = 2.500 USD; bugün kur 50 → 125.000 TL
        let trades = [buy("20", "5000", on: 1, usd: "40")]
        #expect(RealReturn.usdBenchmark(trades: trades, usdTRYNow: 50) == 125_000)
        // Yarısı satılırsa yarısı kalır
        let withSell = trades + [sell("10", "6000", on: 2)]
        #expect(RealReturn.usdBenchmark(trades: withSell, usdTRYNow: 50) == 62_500)
        // Kuru bilinmeyen alım → hesaplanamaz
        #expect(RealReturn.usdBenchmark(trades: [buy("1", "5000", on: 1)], usdTRYNow: 50) == nil)
    }

    @Test("Reel getiri: TÜFE karşılaştırması (yapay endeks)")
    func cpiBenchmark() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let jan = LedgerMonth(containing: day(1), calendar: cal)
        let table = RealReturn.CPITable([jan: 100, jan.next: 103, jan.next.next: 110])
        let trades = [buy("10", "5000", on: 1), buy("10", "5500", on: 35)] // Ocak ve Şubat
        // 50.000 × 110/100 + 55.000 × 110/103
        let expected = Decimal(50_000) * 110 / 100 + Decimal(55_000) * 110 / 103
        #expect(RealReturn.cpiBenchmark(trades: trades, cpi: table, calendar: cal) == expected)
        let missing = RealReturn.CPITable([jan.next: 103])
        #expect(RealReturn.cpiBenchmark(trades: trades, cpi: missing, calendar: cal) == nil)
    }
}

@Suite("Alım/satım taslağı (REQ-P1)")
struct TradeDraftTests {
    let now = day(10)

    @Test func valid() {
        let draft = TradeDraft(asset: gram, side: .buy, quantity: d("2.5"), unitPrice: 5900, date: day(9))
        #expect(draft.issues(existing: [], now: now).isEmpty)
        #expect(draft.total == d("14750"))
    }

    @Test func missingFields() {
        let issues = TradeDraft(date: day(9)).issues(existing: [], now: now)
        #expect(issues == [.missingAsset, .missingQuantity, .missingPrice])
    }

    @Test("Çeyrek altın küsuratlı adet olamaz")
    func pieces() {
        let draft = TradeDraft(asset: .gold(.quarter), quantity: d("1.5"), unitPrice: 10_000, date: day(9))
        #expect(draft.issues(existing: [], now: now) == [.fractionalPieces])
    }

    @Test("Gelecek tarih reddedilir")
    func future() {
        let draft = TradeDraft(asset: gram, quantity: 1, unitPrice: 5000, date: day(11))
        #expect(draft.issues(existing: [], now: now) == [.futureDate])
    }

    @Test("Elde olandan fazla satış uyarısı")
    func oversell() {
        let existing = [buy("3", "5000", on: 1)]
        let draft = TradeDraft(asset: gram, side: .sell, quantity: 4, unitPrice: 6000, date: day(9))
        #expect(draft.issues(existing: existing, now: now) == [.oversell(available: 3)])
        let ok = TradeDraft(asset: gram, side: .sell, quantity: 3, unitPrice: 6000, fee: 50, date: day(9))
        #expect(ok.issues(existing: existing, now: now).isEmpty)
        #expect(ok.total == 17_950)
    }
}

@Suite("Portföy geçmişi (REQ-P8)")
struct PortfolioHistoryTests {
    @Test("Gün gün eldeki miktar × son bilinen fiyat")
    func series() {
        let trades = [buy("10", "5000", on: 1), buy("5", "5600", on: 3), sell("3", "6000", on: 5)]
        let prices: [AssetCode: [(date: Date, price: Decimal)]] = [gram: [(day(1), 5000), (day(3), 5600), (day(4), 5800)]]
        let points = PortfolioHistory.series(trades: trades, prices: prices, days: [day(0), day(1), day(2), day(3), day(4), day(5)])
        #expect(points.map(\.value) == [50_000, 50_000, 84_000, 87_000, 69_600])
        #expect(points.first?.date == day(1), "işlem öncesi gün atlanır")
    }

    @Test("Fiyatı bilinmeyen varlık o gün toplama girmez")
    func unknownPrice() {
        let usd = Trade(asset: .fx(.USD), side: .buy, quantity: 100, unitPrice: 40, date: day(1))
        let trades = [buy("1", "5000", on: 1), usd]
        let points = PortfolioHistory.series(trades: trades, prices: [gram: [(day(1), 5000)]], days: [day(2)])
        #expect(points.map(\.value) == [5000])
    }
}
