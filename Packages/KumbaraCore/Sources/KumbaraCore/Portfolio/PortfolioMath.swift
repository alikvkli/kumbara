import Foundation

/// Bir varlık alım/satımı (specs/03 §1). Fiyat ve ücret TRY cinsinden.
public struct Trade: Hashable, Sendable, Identifiable {
    public enum Side: String, Sendable, Codable { case buy, sell }

    public var id: UUID
    public var asset: AssetCode
    public var side: Side
    public var quantity: Decimal
    public var unitPrice: Decimal
    /// Toplam ek maliyet (işçilik, komisyon).
    public var fee: Decimal
    public var date: Date
    /// İşlem anındaki USD/TRY; reel getiri için kaydedilir, sonradan çekilmez (specs/03 §4).
    public var usdTRYAtTrade: Decimal?

    public init(id: UUID = UUID(), asset: AssetCode, side: Side, quantity: Decimal, unitPrice: Decimal,
                fee: Decimal = 0, date: Date, usdTRYAtTrade: Decimal? = nil) {
        self.id = id
        self.asset = asset
        self.side = side
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.fee = fee
        self.date = date
        self.usdTRYAtTrade = usdTRYAtTrade
    }

    /// Alımda ödenen toplam (miktar × fiyat + ücret).
    public var grossCost: Decimal { quantity * unitPrice + fee }
}

public enum CostMethod: String, Sendable, Codable, CaseIterable {
    /// Ağırlıklı ortalama (varsayılan, D7).
    case averageCost
    case fifo
}

public enum PortfolioError: Error, Equatable {
    /// Elde olandan fazla satış.
    case oversell(tradeID: UUID, available: Decimal, requested: Decimal)
    case invalidTrade(tradeID: UUID)
    case mixedAssets
}

/// Bir pozisyonun işlemlerden hesaplanmış durumu (specs/03 §2).
public struct Position: Hashable, Sendable {
    public struct Lot: Hashable, Sendable {
        public var quantity: Decimal
        /// Ücret dahil birim maliyet.
        public var unitCost: Decimal
        public var date: Date
    }

    public let asset: AssetCode
    public let method: CostMethod
    public private(set) var quantity: Decimal = 0
    /// Eldeki miktarın toplam maliyeti (ücret dahil).
    public private(set) var costBasis: Decimal = 0
    /// Satışlardan gerçekleşmiş kâr/zarar (REQ-P6).
    public private(set) var realizedPnL: Decimal = 0
    /// FIFO'da açık lotlar; ortalama yöntemde tek birleşik lot.
    public private(set) var lots: [Lot] = []

    public var averageCost: Decimal? { quantity > 0 ? costBasis / quantity : nil }
    public var isOpen: Bool { quantity > 0 }

    /// İşlemler tarih sırasına dizilir (eşit tarihte verilen sıra korunur).
    public init(asset: AssetCode, trades: [Trade], method: CostMethod = .averageCost) throws {
        self.asset = asset
        self.method = method
        let ordered = trades.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        for trade in ordered {
            guard trade.asset == asset else { throw PortfolioError.mixedAssets }
            guard trade.quantity > 0, trade.unitPrice >= 0, trade.fee >= 0 else {
                throw PortfolioError.invalidTrade(tradeID: trade.id)
            }
            switch trade.side {
            case .buy: applyBuy(trade)
            case .sell: try applySell(trade)
            }
        }
    }

    private mutating func applyBuy(_ trade: Trade) {
        quantity += trade.quantity
        costBasis += trade.grossCost
        let unitCost = trade.grossCost / trade.quantity
        switch method {
        case .averageCost:
            lots = [Lot(quantity: quantity, unitCost: costBasis / quantity, date: lots.first?.date ?? trade.date)]
        case .fifo:
            lots.append(Lot(quantity: trade.quantity, unitCost: unitCost, date: trade.date))
        }
    }

    private mutating func applySell(_ trade: Trade) throws {
        guard trade.quantity <= quantity else {
            throw PortfolioError.oversell(tradeID: trade.id, available: quantity, requested: trade.quantity)
        }
        let proceeds = trade.quantity * trade.unitPrice - trade.fee
        let removedCost: Decimal
        switch method {
        case .averageCost:
            let average = costBasis / quantity
            removedCost = trade.quantity * average
            quantity -= trade.quantity
            costBasis -= removedCost
            lots = quantity > 0 ? [Lot(quantity: quantity, unitCost: average, date: lots.first?.date ?? trade.date)] : []
        case .fifo:
            var remaining = trade.quantity
            var cost: Decimal = 0
            while remaining > 0, !lots.isEmpty {
                let take = min(remaining, lots[0].quantity)
                cost += take * lots[0].unitCost
                lots[0].quantity -= take
                remaining -= take
                if lots[0].quantity == 0 { lots.removeFirst() }
            }
            removedCost = cost
            quantity -= trade.quantity
            costBasis = lots.reduce(0) { $0 + $1.quantity * $1.unitCost }
        }
        realizedPnL += proceeds - removedCost
        if quantity == 0 { costBasis = 0 }
    }
}

/// Pozisyonun güncel fiyatla değerlemesi (specs/03 §3).
public struct Valuation: Hashable, Sendable {
    public let priceKind: PriceKind
    public let unitPrice: Decimal
    public let value: Decimal
    public let unrealizedPnL: Decimal
    /// Maliyet sıfırsa `nil`.
    public let unrealizedReturn: Decimal?
    /// "Şimdi alıp hemen satsan kaybın": miktar × (satış − alış). Makas bilinmiyorsa `nil`.
    public let spreadCost: Decimal?
    public let totalPnL: Decimal

    public init(position: Position, quote: Quote, priceKind: PriceKind = .bid) {
        precondition(quote.asset == position.asset)
        self.priceKind = priceKind
        unitPrice = quote.price(priceKind)
        value = position.quantity * unitPrice
        unrealizedPnL = value - position.costBasis
        unrealizedReturn = position.costBasis > 0 ? unrealizedPnL / position.costBasis : nil
        spreadCost = quote.spread.map { position.quantity * $0 }
        totalPnL = position.realizedPnL + unrealizedPnL
    }
}

/// Reel getiri karşılaştırmaları (specs/03 §4, REQ-P7).
public enum RealReturn {
    /// Aynı paralar alım günlerinde USD'ye çevrilip bugün geri bozulsaydı (yalnız açık maliyet için:
    /// satışlar ortalama maliyet oranında düşülür). Kuru eksik alım varsa `nil`.
    public static func usdBenchmark(trades: [Trade], usdTRYNow: Decimal) -> Decimal? {
        var usdHeld: Decimal = 0
        var quantity: Decimal = 0
        for trade in trades.sorted(by: { $0.date < $1.date }) {
            switch trade.side {
            case .buy:
                guard let rate = trade.usdTRYAtTrade, rate > 0 else { return nil }
                usdHeld += trade.grossCost / rate
                quantity += trade.quantity
            case .sell:
                guard quantity > 0 else { return nil }
                usdHeld -= usdHeld * (trade.quantity / quantity)
                quantity -= trade.quantity
            }
        }
        return usdHeld * usdTRYNow
    }

    /// Aylık TÜFE endeksi (ör. TÜİK 2003=100). Anahtar ayın ilk günü değil, `LedgerMonth`.
    public struct CPITable: Sendable {
        public var index: [LedgerMonth: Decimal]
        public init(_ index: [LedgerMonth: Decimal]) { self.index = index }

        /// Bilinen en son ay.
        public var latest: (month: LedgerMonth, value: Decimal)? {
            index.max { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
    }

    /// Açık maliyet TÜFE ile bugüne taşınsaydı. Endeksi eksik alım varsa `nil`.
    /// "Bugün" tablodaki son aydır (TÜFE ayda bir açıklanır).
    public static func cpiBenchmark(trades: [Trade], cpi: CPITable, calendar: Calendar) -> Decimal? {
        guard let latest = cpi.latest else { return nil }
        var adjusted: Decimal = 0
        var quantity: Decimal = 0
        for trade in trades.sorted(by: { $0.date < $1.date }) {
            switch trade.side {
            case .buy:
                let month = LedgerMonth(containing: trade.date, calendar: calendar)
                // Tablonun son ayından sonraki alımlar için henüz enflasyon yok: son ay kullanılır.
                let base = cpi.index[month] ?? (month > latest.month ? latest.value : nil)
                guard let base, base > 0 else { return nil }
                adjusted += trade.grossCost * latest.value / base
                quantity += trade.quantity
            case .sell:
                guard quantity > 0 else { return nil }
                adjusted -= adjusted * (trade.quantity / quantity)
                quantity -= trade.quantity
            }
        }
        return adjusted
    }
}
