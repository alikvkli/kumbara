import Foundation

/// Kullanıcının doldurduğu alım/satım formu (REQ-P1, P5).
public struct TradeDraft: Hashable, Sendable {
    public var asset: AssetCode?
    public var side: Trade.Side
    public var quantity: Decimal?
    public var unitPrice: Decimal?
    public var fee: Decimal
    public var date: Date
    public var note: String

    public init(asset: AssetCode? = nil, side: Trade.Side = .buy, quantity: Decimal? = nil,
                unitPrice: Decimal? = nil, fee: Decimal = 0, date: Date = .now, note: String = "") {
        self.asset = asset
        self.side = side
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.fee = fee
        self.date = date
        self.note = note
    }

    public enum Issue: Hashable, Sendable {
        case missingAsset
        case missingQuantity
        case nonPositiveQuantity
        /// Adetli varlıkta (çeyrek vb.) küsuratlı miktar.
        case fractionalPieces
        case missingPrice
        case nonPositivePrice
        case negativeFee
        case futureDate
        /// Elde olandan fazla satış (pozisyon hesaplanınca).
        case oversell(available: Decimal)
    }

    /// `existing`: bu varlığın kayıtlı işlemleri (düzenlenen işlem hariç). Satış kontrolü için.
    public func issues(existing: [Trade], now: Date = .now) -> [Issue] {
        var result: [Issue] = []
        if asset == nil { result.append(.missingAsset) }
        switch quantity {
        case nil: result.append(.missingQuantity)
        case let q? where q <= 0: result.append(.nonPositiveQuantity)
        case let q?:
            if asset?.unit == .piece, q.rounded(scale: 0, .plain) != q { result.append(.fractionalPieces) }
        }
        switch unitPrice {
        case nil: result.append(.missingPrice)
        case let p? where p <= 0: result.append(.nonPositivePrice)
        default: break
        }
        if fee < 0 { result.append(.negativeFee) }
        if date > now.addingTimeInterval(60) { result.append(.futureDate) }

        if result.isEmpty, let trade = trade(id: UUID()) {
            do {
                _ = try Position(asset: trade.asset, trades: existing + [trade])
            } catch PortfolioError.oversell(_, let available, _) {
                result.append(.oversell(available: available))
            } catch {
                result.append(.nonPositiveQuantity)
            }
        }
        return result
    }

    /// Geçerliyse `Trade` değeri (kimlik verilerek).
    public func trade(id: UUID, usdTRYAtTrade: Decimal? = nil) -> Trade? {
        guard let asset, let quantity, quantity > 0, let unitPrice, unitPrice > 0, fee >= 0 else { return nil }
        return Trade(id: id, asset: asset, side: side, quantity: quantity, unitPrice: unitPrice,
                     fee: fee, date: date, usdTRYAtTrade: usdTRYAtTrade)
    }

    /// Satırdaki toplam: alımda ödenen, satımda eline geçen.
    public var total: Decimal? {
        guard let quantity, let unitPrice else { return nil }
        return side == .buy ? quantity * unitPrice + fee : quantity * unitPrice - fee
    }
}

/// Portföyün zaman içindeki değeri (REQ-P8). Her gün için o güne kadarki işlemlerle eldeki miktar ×
/// o gün veya öncesindeki son bilinen fiyat. Fiyatı hiç bilinmeyen varlık o gün atlanır.
public enum PortfolioHistory {
    public struct Point: Hashable, Sendable {
        public let date: Date
        public let value: Decimal

        public init(date: Date, value: Decimal) {
            self.date = date
            self.value = value
        }
    }

    /// `prices`: varlık → (gün, birim fiyat) listesi. `days`: hangi günler için nokta üretileceği.
    public static func series(trades: [Trade], prices: [AssetCode: [(date: Date, price: Decimal)]],
                              days: [Date]) -> [Point] {
        let byAsset = Dictionary(grouping: trades, by: \.asset)
        let sortedPrices = prices.mapValues { $0.sorted { $0.date < $1.date } }
        return days.sorted().compactMap { day in
            var total: Decimal = 0
            var priced = false
            for (asset, assetTrades) in byAsset {
                let quantity = assetTrades.filter { $0.date <= day }.reduce(Decimal(0)) {
                    $0 + ($1.side == .buy ? $1.quantity : -$1.quantity)
                }
                guard quantity > 0 else { continue }
                guard let price = sortedPrices[asset]?.last(where: { $0.date <= day })?.price else { continue }
                total += quantity * price
                priced = true
            }
            return priced ? Point(date: day, value: total) : nil
        }
    }
}
