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

extension ProviderID {
    var label: String {
        switch self {
        case .truncgil: "Truncgil"
        case .goldAPI: "gold-api"
        case .tcmb: "TCMB"
        case .frankfurter: "ECB"
        case .coingecko: "CoinGecko"
        case .manual: String(localized: "Elle")
        }
    }
}

/// Uygulama ayarları anahtarları (`@AppStorage`).
enum SettingsKey {
    static let priceKind = "valuation.priceKind"
    static let costMethod = "valuation.costMethod"
}

/// "Bozdurma · Truncgil · 07:16" ve tazelik uyarısı (C4, C6, specs/06 §2.4).
struct QuoteProvenance: View {
    let quote: Quote?
    let priceKind: PriceKind
    let freshness: Freshness?
    var isOffline = false

    var body: some View {
        HStack(spacing: 4) {
            if let quote {
                Text(priceKind.shortLabel)
                Text(verbatim: "·")
                Text(verbatim: quote.source.label + (quote.isDerived ? " ≈" : ""))
                Text(verbatim: "·")
                Text(quote.asOf, format: .dateTime.hour().minute())
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
