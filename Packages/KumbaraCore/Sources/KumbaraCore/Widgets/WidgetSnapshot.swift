import Foundation

/// Uygulamanın widget'lar ve menü çubuğu için App Group'a yazdığı küçük özet (specs/09 §4).
/// Widget SwiftData açmaz: bu dosyayı okur, fiyatı fırsat buldukça kendisi tazeler.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Price: Codable, Hashable, Sendable {
        public var assetID: String
        public var name: String
        public var price: Decimal
        /// Önceki güne göre değişim oranı (0,012 = %1,2); bilinmiyorsa `nil`.
        public var dayChange: Decimal?
        public var asOf: Date

        public init(assetID: String, name: String, price: Decimal, dayChange: Decimal?, asOf: Date) {
            self.assetID = assetID
            self.name = name
            self.price = price
            self.dayChange = dayChange
            self.asOf = asOf
        }
    }

    public struct Holding: Codable, Hashable, Sendable {
        public var name: String
        public var value: Decimal
        public var pnlRatio: Decimal?

        public init(name: String, value: Decimal, pnlRatio: Decimal?) {
            self.name = name
            self.value = value
            self.pnlRatio = pnlRatio
        }
    }

    public struct Budget: Codable, Hashable, Sendable {
        /// Bugün harcanabilecek (genel bütçeden ya da ayın netinden).
        public var perDay: Decimal
        public var remainingDays: Int
        /// Genel bütçe varsa harcanan/limit; yoksa `nil`.
        public var spentFraction: Double?
        public var remaining: Decimal

        public init(perDay: Decimal, remainingDays: Int, spentFraction: Double?, remaining: Decimal) {
            self.perDay = perDay
            self.remainingDays = remainingDays
            self.spentFraction = spentFraction
            self.remaining = remaining
        }
    }

    /// Yaklaşan ödeme (specs/10 §5): widget yalnız bugünden sonrakileri gösterir.
    public struct Upcoming: Codable, Hashable, Sendable {
        public var title: String
        public var date: Date
        public var amount: Decimal
        public var isIncome: Bool
        public var isEstimate: Bool

        public init(title: String, date: Date, amount: Decimal, isIncome: Bool, isEstimate: Bool) {
            self.title = title
            self.date = date
            self.amount = amount
            self.isIncome = isIncome
            self.isEstimate = isEstimate
        }
    }

    public var createdAt: Date
    public var prices: [Price]
    public var portfolioTotal: Decimal?
    public var portfolioPnL: Decimal?
    public var portfolioPnLRatio: Decimal?
    public var holdings: [Holding]
    public var budget: Budget?
    /// "Widget'ta tutarları gizle" (kilit ayarı); fiyatlar gizlenmez, kişisel tutarlar gizlenir.
    public var hidesAmounts: Bool
    /// Önümüzdeki 30 günün ödemeleri; eski özetlerde yok.
    public var upcoming: [Upcoming]?

    public init(createdAt: Date, prices: [Price], portfolioTotal: Decimal?, portfolioPnL: Decimal?,
                portfolioPnLRatio: Decimal?, holdings: [Holding], budget: Budget?, hidesAmounts: Bool,
                upcoming: [Upcoming]? = nil) {
        self.upcoming = upcoming
        self.createdAt = createdAt
        self.prices = prices
        self.portfolioTotal = portfolioTotal
        self.portfolioPnL = portfolioPnL
        self.portfolioPnLRatio = portfolioPnLRatio
        self.holdings = holdings
        self.budget = budget
        self.hidesAmounts = hidesAmounts
    }

    public static let placeholder = WidgetSnapshot(
        createdAt: .now,
        prices: [Price(assetID: "gold.gram24", name: "Gram altın", price: 6_120, dayChange: Decimal(string: "0.004"), asOf: .now),
                 Price(assetID: "fx.USD", name: "USD", price: Decimal(string: "50.75")!, dayChange: nil, asOf: .now)],
        portfolioTotal: 285_400, portfolioPnL: 41_200, portfolioPnLRatio: Decimal(string: "0.169"),
        holdings: [Holding(name: "Gram altın", value: 107_100, pnlRatio: Decimal(string: "0.21")),
                   Holding(name: "Çeyrek altın", value: 81_300, pnlRatio: Decimal(string: "0.13")),
                   Holding(name: "USD", value: 60_900, pnlRatio: Decimal(string: "0.18"))],
        budget: Budget(perDay: 1_799, remainingDays: 4, spentFraction: 0.84, remaining: 7_194),
        hidesAmounts: false,
        upcoming: [Upcoming(title: "Kira", date: .now.addingTimeInterval(2 * 86_400), amount: 22_500, isIncome: false, isEstimate: false),
                   Upcoming(title: "Kredi kartı", date: .now.addingTimeInterval(5 * 86_400), amount: 8_420, isIncome: false, isEstimate: false),
                   Upcoming(title: "Netflix", date: .now.addingTimeInterval(9 * 86_400), amount: Decimal(string: "229.99")!, isIncome: false, isEstimate: true)])

    /// Fiyatı yeni gelen değerlerle günceller (widget kendi yenilemesinde). Değişim oranı, eski
    /// fiyatın günü bugünden önceyse yeniden hesaplanır; değilse korunur.
    public func updating(price assetID: String, to price: Decimal, asOf: Date, calendar: Calendar) -> WidgetSnapshot {
        var copy = self
        guard let index = copy.prices.firstIndex(where: { $0.assetID == assetID }) else { return copy }
        let old = copy.prices[index]
        guard asOf >= old.asOf else { return copy }
        if !calendar.isDate(old.asOf, inSameDayAs: asOf), old.price > 0 {
            copy.prices[index].dayChange = (price - old.price) / old.price
        }
        copy.prices[index].price = price
        copy.prices[index].asOf = asOf
        return copy
    }
}

/// Anlık görüntünün App Group'taki yeri ve okuma/yazma.
public enum WidgetSnapshotStore {
    public static let fileName = "widget-snapshot.json"

    public static func url(in directory: URL) -> URL { directory.appending(path: fileName) }

    #if canImport(Darwin)
    public static func shared() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CaptureInbox.appGroup).map(url(in:))
    }
    #endif

    public static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
