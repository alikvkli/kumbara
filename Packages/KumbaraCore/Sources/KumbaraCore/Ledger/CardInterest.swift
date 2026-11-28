import Foundation

/// Kredi kartı faiz tavanları (REQ-I8, specs/11 §2). TCMB her ay ilan eder; uygulamayla gelir,
/// kullanıcı kartına uygulanan oranı ayrıca yazabilir (bankalar tavanın altında faiz alabilir).
///
/// Kaynak: TCMB "Kredi Kartı İşlemlerinde Uygulanacak Azami Faiz Oranları" (24 Kasım 2026 duyurusu,
/// 1 Aralık 2026'dan geçerli). Dilim dönem borcuna göre seçilir; kurumsal kartlar ve nakit avans kapsam dışı.
public struct CardInterestRates: Hashable, Sendable {
    public struct Tier: Hashable, Sendable {
        /// Dilimin üst sınırı (dönem borcu, dahil); `nil` son dilim.
        public var upTo: Decimal?
        /// Aylık azami akdi faiz (0,0308 = %3,08).
        public var contractual: Decimal
        /// Aylık azami gecikme faizi.
        public var late: Decimal
    }

    /// İlk geçerli gün (ayın 1'i).
    public var effective: LedgerMonth
    public var tiers: [Tier]
    /// Faize eklenen vergiler: KKDF %15, BSMV %15.
    public var kkdf: Decimal = Decimal(string: "0.15")!
    public var bsmv: Decimal = Decimal(string: "0.15")!

    public func tier(for balance: Decimal) -> Tier {
        tiers.first { $0.upTo.map { balance <= $0 } ?? true } ?? tiers[tiers.count - 1]
    }

    /// Yeniden eskiye. Yeni tablo geldiğinde başa eklenir.
    public static let history: [CardInterestRates] = [
        // 1 Aralık 2026: referans oran %2,94. Son dilimin gecikme faizi duyuruda ayrıca geçmiyor;
        // diğer dilimlerdeki 0,30 puanlık fark korunarak yazıldı (specs/11 §2, doğrulanacak).
        CardInterestRates(effective: LedgerMonth(year: 2026, month: 12), tiers: [
            Tier(upTo: 30_000, contractual: Decimal(string: "0.0308")!, late: Decimal(string: "0.0338")!),
            Tier(upTo: 180_000, contractual: Decimal(string: "0.0358")!, late: Decimal(string: "0.0388")!),
            Tier(upTo: nil, contractual: Decimal(string: "0.0408")!, late: Decimal(string: "0.0438")!),
        ]),
        // 30 Kasım 2026'ya kadar.
        CardInterestRates(effective: LedgerMonth(year: 2024, month: 1), tiers: [
            Tier(upTo: 30_000, contractual: Decimal(string: "0.0325")!, late: Decimal(string: "0.0355")!),
            Tier(upTo: 180_000, contractual: Decimal(string: "0.0375")!, late: Decimal(string: "0.0405")!),
            Tier(upTo: nil, contractual: Decimal(string: "0.0425")!, late: Decimal(string: "0.0455")!),
        ]),
    ]

    /// `date`te geçerli tablo; daha eskiyse en eski tablo.
    public static func current(on date: Date, calendar: Calendar) -> CardInterestRates {
        let month = LedgerMonth(containing: date, calendar: calendar)
        return history.first { $0.effective <= month } ?? history[history.count - 1]
    }
}

/// Asgari ödeme oranı (BDDK, 1 Ekim 2026 kararı): kart limiti ₺100.000 ve altı %20, üstü %40.
public enum MinimumPaymentRule: String, Hashable, Sendable, CaseIterable, Codable {
    case standard
    case high

    public var ratio: Decimal { self == .standard ? Decimal(string: "0.2")! : Decimal(string: "0.4")! }
    public static let limitThreshold: Decimal = 100_000

    public init(limit: Decimal) { self = limit > Self.limitThreshold ? .high : .standard }
}

/// Ekstre borcunun bir dönem sonraki maliyeti ve yalnız asgari ödenirse kapanma süresi (specs/11 §3).
///
/// Basitleştirmeler (ekranda yazar): iki ekstre arası 30 gün sayılır, yeni harcama eklenmez, faiz
/// kalan borca kesimden kesime işler. Yuvarlama her adımda kuruşa (`.plain`).
public enum CardInterest {
    /// Bir sonraki ekstreye yansıyacaklar.
    public struct Outcome: Hashable, Sendable {
        public var balance: Decimal
        public var payment: Decimal
        public var minimum: Decimal
        /// Ödenmeyen kısım.
        public var unpaid: Decimal
        public var contractualInterest: Decimal
        /// Asgari ödenmezse eksik kalan kısma işleyen gecikme faizi.
        public var lateInterest: Decimal
        public var kkdf: Decimal
        public var bsmv: Decimal
        public var interest: Decimal { contractualInterest + lateInterest }
        /// Faiz ve vergiler.
        public var cost: Decimal { interest + kkdf + bsmv }
        /// Gelecek ekstreye devreden (yeni harcama hariç).
        public var carried: Decimal { unpaid + cost }
        public var isBelowMinimum: Bool { payment < minimum }
    }

    /// Hep aynı şekilde ödenirse borcun kapanması.
    public struct Payoff: Hashable, Sendable {
        public var months: Int
        public var totalPaid: Decimal
        public var totalCost: Decimal
        public var firstPayment: Decimal
        /// `maxMonths` içinde kapanmadıysa `false` (ödeme faizi karşılamıyor).
        public var finishes: Bool
    }

    public enum Plan: Hashable, Sendable {
        /// Her ay o ayın asgarisi.
        case minimum
        /// Her ay sabit tutar (asgariden azsa asgari).
        case fixed(Decimal)
    }

    /// Kalan borç bu tutara inince o ay tamamı ödenmiş sayılır (asgari kuyruğu sonsuza uzamasın).
    public static let closingThreshold: Decimal = 100

    public static func minimum(balance: Decimal, rule: MinimumPaymentRule) -> Decimal {
        max(balance, 0) <= closingThreshold ? max(balance, 0) : (balance * rule.ratio).rounded(scale: 2)
    }

    /// `rate` verilirse (kartın kendi akdi faizi) tavan yerine o kullanılır; gecikme faizi tavandan,
    /// akdi faizin üstüne tavandaki fark eklenerek.
    public static func outcome(balance: Decimal, payment: Decimal, rule: MinimumPaymentRule,
                               rates: CardInterestRates, rate: Decimal? = nil) -> Outcome {
        let balance = max(balance, 0)
        let payment = min(max(payment, 0), balance)
        let minimum = minimum(balance: balance, rule: rule)
        let tier = rates.tier(for: balance)
        let contractualRate = rate ?? tier.contractual
        let lateRate = contractualRate + (tier.late - tier.contractual)
        let shortfall = max(minimum - payment, 0)
        let unpaid = balance - payment
        let contractual = ((unpaid - shortfall) * contractualRate).rounded(scale: 2)
        let late = (shortfall * lateRate).rounded(scale: 2)
        let interest = contractual + late
        return Outcome(balance: balance, payment: payment, minimum: minimum, unpaid: unpaid,
                       contractualInterest: contractual, lateInterest: late,
                       kkdf: (interest * rates.kkdf).rounded(scale: 2), bsmv: (interest * rates.bsmv).rounded(scale: 2))
    }

    public static func payoff(balance: Decimal, plan: Plan, rule: MinimumPaymentRule, rates: CardInterestRates,
                              rate: Decimal? = nil, maxMonths: Int = 360) -> Payoff {
        var remaining = max(balance, 0)
        var months = 0
        var paid: Decimal = 0
        var first: Decimal?
        while remaining > 0, months < maxMonths {
            let minimum = minimum(balance: remaining, rule: rule)
            let payment: Decimal = switch plan {
            case .minimum: minimum
            case let .fixed(amount): min(max(amount, minimum), remaining)
            }
            let step = outcome(balance: remaining, payment: payment, rule: rule, rates: rates, rate: rate)
            months += 1
            paid += payment
            if first == nil { first = payment }
            remaining = step.carried
        }
        return Payoff(months: months, totalPaid: paid, totalCost: paid - max(balance, 0) + remaining,
                      firstPayment: first ?? 0, finishes: remaining == 0)
    }
}
