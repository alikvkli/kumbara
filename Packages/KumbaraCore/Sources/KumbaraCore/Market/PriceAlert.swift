import Foundation

/// Fiyat alarmı (REQ-M4, specs/08 §5). Bir kez çalar: eşik **geçildiği anda**; kurulduğunda koşul
/// zaten sağlanıyorsa çalmaz, fiyat eşiğin öbür yanında kaldıkça tekrar çalmaz.
public struct PriceAlertRule: Hashable, Sendable {
    public enum Direction: String, Sendable, Codable, CaseIterable {
        /// Fiyat eşiğe eşit ya da üstüne çıkınca.
        case above
        /// Fiyat eşiğe eşit ya da altına düşünce.
        case below
    }

    public var asset: AssetCode
    public var direction: Direction
    public var threshold: Decimal
    public var priceKind: PriceKind

    public init(asset: AssetCode, direction: Direction, threshold: Decimal, priceKind: PriceKind = .bid) {
        self.asset = asset
        self.direction = direction
        self.threshold = threshold
        self.priceKind = priceKind
    }

    /// Fiyat koşulu sağlıyor mu. Tahmini (ons fiyatından türetilmiş) ve elle girilen fiyat sayılmaz:
    /// yanlış alarmı önlemek için ilk gerçek fiyat beklenir.
    public func isSatisfied(by quote: Quote) -> Bool? {
        guard quote.asset == asset, !quote.isDerived, quote.source != .manual else { return nil }
        let price = quote.price(priceKind)
        return direction == .above ? price >= threshold : price <= threshold
    }

    public struct Evaluation: Equatable, Sendable {
        /// Bildirim gönderilmeli mi.
        public var fires: Bool
        /// Kaydedilecek son durum (bir sonraki değerlendirmenin "önceki"si).
        public var satisfied: Bool?
    }

    /// `previous`: bir önceki gerçek fiyattaki durum (`nil` = henüz bilinmiyor; kurulduğu an).
    /// Çalma yalnız `false → true` geçişinde olur.
    public func evaluate(_ quote: Quote, previous: Bool?) -> Evaluation {
        guard let now = isSatisfied(by: quote) else { return Evaluation(fires: false, satisfied: previous) }
        return Evaluation(fires: previous == false && now, satisfied: now)
    }
}
