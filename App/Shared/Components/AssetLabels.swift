import KumbaraCore
import KumbaraData
import SwiftUI

extension AssetCode {
    /// Kullanıcıya gösterilen ad. Serbest varlıkta `customName` verilmeli.
    func displayName(customName: String? = nil) -> String {
        switch self {
        case .gold(let kind):
            switch kind {
            case .gram24: String(localized: "Gram altın")
            case .has: String(localized: "Has altın")
            case .bracelet22: String(localized: "22 ayar bilezik")
            case .carat18: String(localized: "18 ayar altın")
            case .carat14: String(localized: "14 ayar altın")
            case .quarter: String(localized: "Çeyrek altın")
            case .half: String(localized: "Yarım altın")
            case .full: String(localized: "Tam altın")
            case .republic: String(localized: "Cumhuriyet altını")
            case .ata: String(localized: "Ata altın")
            case .resat: String(localized: "Reşat altın")
            case .hamit: String(localized: "Hamit altın")
            case .gremse: String(localized: "Gremse altın")
            case .ikibucuk: String(localized: "İkibuçuk altın")
            case .besli: String(localized: "Beşli altın")
            }
        case .metal(let metal):
            switch metal {
            case .silver: String(localized: "Gümüş")
            case .platinum: String(localized: "Platin")
            case .palladium: String(localized: "Paladyum")
            }
        case .fx(let code):
            Locale.current.localizedString(forCurrencyCode: code.rawValue).map { "\(code.rawValue) · \($0)" } ?? code.rawValue
        case .crypto(let id):
            Self.cryptoNames[id] ?? id.capitalized
        case .custom:
            customName ?? String(localized: "Serbest varlık")
        }
    }

    /// Kısa ad (şerit, tablo): "Gram", "USD", "BTC".
    var shortName: String {
        switch self {
        case .gold(.gram24): String(localized: "Gram")
        case .gold, .metal: displayName()
        case .fx(let code): code.rawValue
        case .crypto(let id): Self.cryptoSymbols[id] ?? id.uppercased()
        case .custom: displayName()
        }
    }

    /// Miktar birimi: "g", "adet", "USD", "BTC".
    var unitLabel: String {
        switch self {
        case .fx(let code): code.rawValue
        case .crypto(let id): Self.cryptoSymbols[id] ?? id.uppercased()
        case .custom: String(localized: "birim")
        default: unit == .gram ? String(localized: "g") : String(localized: "adet")
        }
    }

    var systemImage: String {
        switch self {
        case .gold, .metal: "circle.circle"
        case .fx(let code):
            switch code.rawValue {
            case "USD": "dollarsign"
            case "EUR": "eurosign"
            case "GBP": "sterlingsign"
            case "CHF": "francsign"
            default: "banknote"
            }
        case .crypto: "bitcoinsign"
        case .custom: "chart.bar"
        }
    }

    var tint: Color {
        switch self {
        case .gold: Color(red: 0.89, green: 0.69, blue: 0.24)
        case .metal(.silver): .gray
        case .metal: .secondary
        case .fx: .teal
        case .crypto: .orange
        case .custom: .indigo
        }
    }

    /// Birim fiyat gösterimi: adetli altın küsuratsız (₺10.229), diğerleri her zaman 2 hane (₺5.906,50).
    func formatPrice(_ value: Decimal, locale: Locale) -> String {
        value.formattedNumber(locale: locale, fractionDigits: unit == .piece ? 0...0 : 2...2)
    }

    static let cryptoNames: [String: String] = ["bitcoin": "Bitcoin", "ethereum": "Ethereum", "tether": "Tether",
                                                "solana": "Solana", "ripple": "XRP", "avalanche-2": "Avalanche"]
    static let cryptoSymbols: [String: String] = ["bitcoin": "BTC", "ethereum": "ETH", "tether": "USDT",
                                                  "solana": "SOL", "ripple": "XRP", "avalanche-2": "AVAX"]
}

extension PriceKind {
    var label: LocalizedStringKey {
        switch self {
        case .bid: "Bozdurma (alış)"
        case .ask: "Satış"
        case .mid: "Orta"
        }
    }

    var shortLabel: LocalizedStringKey {
        switch self {
        case .bid: "Bozdurma"
        case .ask: "Satış"
        case .mid: "Orta fiyat"
        }
    }
}

extension CostMethod {
    var label: LocalizedStringKey {
        switch self {
        case .averageCost: "Ağırlıklı ortalama"
        case .fifo: "İlk giren ilk çıkar (FIFO)"
        }
    }
}

/// "az önce", "5 dk önce", "dün 18:05": kendini yenileyen göreli zaman (specs/06 §2.4).
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: RelativeAge.of(date, now: .now, calendar: .current).refreshInterval)) { context in
            Self.text(for: date, now: context.date)
        }
    }

    static func text(for date: Date, now: Date = .now) -> Text {
        switch RelativeAge.of(date, now: now, calendar: .current) {
        case .justNow: Text("az önce")
        case .minutes(let n): Text("\(n) dk önce")
        case .hours(let n): Text("\(n) sa önce")
        case .yesterday(let d): Text("dün \(d.formatted(date: .omitted, time: .shortened))")
        case .earlier(let d): Text(d, format: .dateTime.day().month(.abbreviated).hour().minute())
        }
    }
}

extension Quote {
    /// Kullanıcıya kaynak adı yerine fiyatın niteliği söylenir: hesaplanan ya da elle girilen.
    var originNote: LocalizedStringKey? {
        if source == .manual { return "elle girildi" }
        if isDerived { return "tahmini" }
        return nil
    }
}

/// Uygulama ayarları anahtarları (`@AppStorage`).
enum SettingsKey {
    static let priceKind = "valuation.priceKind"
    static let costMethod = "valuation.costMethod"
    static let smartCheck = "capture.smartCheck"
}

/// "Bozdurma · 5 dk önce" ve tazelik uyarısı (C4, C6, specs/06 §2.4). Sağlayıcı adı gösterilmez.
struct QuoteProvenance: View {
    let quote: Quote?
    let priceKind: PriceKind
    let freshness: Freshness?
    var isOffline = false

    var body: some View {
        HStack(spacing: 4) {
            if let quote {
                Text(priceKind.shortLabel)
                if let note = quote.originNote {
                    Text(verbatim: "·")
                    Text(note)
                }
                Text(verbatim: "·")
                RelativeTimeText(date: quote.asOf)
                if isOffline {
                    Label("çevrimdışı", systemImage: "wifi.slash").labelStyle(.titleAndIcon).foregroundStyle(.orange)
                } else if freshness == .stale {
                    Label("eski fiyat", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
                } else if freshness == .delayed {
                    Text("gecikmeli").foregroundStyle(.orange)
                }
            } else {
                Text("Fiyat henüz yok")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Varlık sembolü: kategori rozetiyle aynı dil (yalnız SF Symbol, renk anlamlı).
struct AssetBadge: View {
    let asset: AssetCode

    var body: some View {
        CategoryBadge(systemImage: asset.systemImage, color: asset.tint)
    }
}
