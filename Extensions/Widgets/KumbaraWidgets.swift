import KumbaraCore
import KumbaraMarket
import SwiftUI
import WidgetKit

/// Widget'lar ve Denetim Merkezi kontrolleri (REQ-X5, X8; specs/09 §4, specs/06 §8).
/// Uygulamanın App Group'a yazdığı özeti okur; fiyatları zaman çizelgesi yenilenirken kendisi de tazeler.
@main
struct KumbaraWidgets: WidgetBundle {
    var body: some Widget {
        PriceWidget()
        BudgetWidget()
        PortfolioWidget()
        UpcomingWidget()
        #if os(iOS)
        AddExpenseControl()
        ScanReceiptControl()
        #endif
    }
}

// MARK: - Zaman çizelgesi

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        let stored = WidgetSnapshotStore.shared().flatMap(WidgetSnapshotStore.read(from:))
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (stored ?? .placeholder) : stored))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        Task {
            let snapshot = await Self.refreshedSnapshot()
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
            completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: snapshot)], policy: .after(next)))
        }
    }

    /// Özetteki fiyatları ağdan tazeler; ağ yoksa özet olduğu gibi kalır (fiyatın yaşı widget'ta yazar).
    static func refreshedSnapshot() async -> WidgetSnapshot? {
        guard var snapshot = WidgetSnapshotStore.shared().flatMap(WidgetSnapshotStore.read(from:)) else { return nil }
        let assets = Set(snapshot.prices.compactMap { AssetCode(id: $0.assetID) })
        guard !assets.isEmpty else { return snapshot }
        let result = await MarketService().refresh(assets)
        for (asset, quote) in result.quotes where !quote.isDerived {
            snapshot = snapshot.updating(price: asset.id, to: quote.price(.bid), asOf: quote.asOf, calendar: .current)
        }
        return snapshot
    }
}

// MARK: - Biçim

enum WidgetFormat {
    static func price(_ price: WidgetSnapshot.Price) -> String {
        let pieces = AssetCode(id: price.assetID)?.unit == .piece
        return price.price.formattedNumber(fractionDigits: pieces || price.price >= 1000 ? 0...0 : 2...2)
    }

    static func money(_ value: Decimal, hidden: Bool) -> String {
        hidden ? "•••" : Money(value, .TRY).formatted(fractionDigits: 0)
    }

    static func change(_ value: Decimal) -> String {
        (value > 0 ? "▲ " : value < 0 ? "▼ " : "") + abs(value).formattedPercent(fractionDigits: 1)
    }
}

/// Fiyatın yaşı: "az önce", "2 sa önce". Widget'ta saat göstermek yerine okunur süre (C6).
struct AgeText: View {
    let date: Date

    var body: some View {
        Text(date, style: .relative)
            .monospacedDigit()
    }
}

struct EmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "circle.circle").font(.title3).foregroundStyle(.tint)
            Text("Kumbara'yı bir kez aç").font(.subheadline.weight(.semibold))
            Text("Bilgiler uygulamayı açınca burada görünür.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Fiyat (küçük, kilit ekranı satır içi / dikdörtgen)

struct PriceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "price", provider: SnapshotProvider()) { entry in
            PriceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DeepLinkURL.market)
        }
        .configurationDisplayName("Gram altın")
        .description("Gram altın ve dolar, bozdurma fiyatıyla.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryInline, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }
}

struct PriceWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let gram = snapshot.prices.first {
            switch family {
            #if os(iOS)
            case .accessoryInline:
                Text(verbatim: "\(gram.name) \(WidgetFormat.price(gram)) ₺")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: gram.name).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "\(WidgetFormat.price(gram)) ₺").font(.headline).widgetAccentable()
                    if let change = gram.dayChange { Text(verbatim: WidgetFormat.change(change)).font(.caption) }
                }
                .monospacedDigit()
            #endif
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: gram.name).font(.subheadline).foregroundStyle(.secondary)
                    Text(verbatim: WidgetFormat.price(gram))
                        .font(.title.weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .widgetAccentable()
                    if let change = gram.dayChange {
                        Text(verbatim: WidgetFormat.change(change)).font(.subheadline.weight(.medium))
                    }
                    Spacer(minLength: 0)
                    ForEach(snapshot.prices.dropFirst().prefix(1), id: \.assetID) { other in
                        HStack {
                            Text(verbatim: other.name).foregroundStyle(.secondary)
                            Spacer()
                            Text(verbatim: WidgetFormat.price(other))
                        }
                        .font(.caption)
                    }
                    AgeText(date: gram.asOf).font(.caption2).foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            EmptyWidgetView()
        }
    }
}

// MARK: - Bütçe (küçük, kilit ekranı dairesel / dikdörtgen)

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "budget", provider: SnapshotProvider()) { entry in
            BudgetWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DeepLinkURL.budget)
        }
        .configurationDisplayName("Bugün harcayabileceğin")
        .description("Bütçene göre bugün ne kadar harcayabileceğin.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }
}

struct BudgetWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let budget = snapshot.budget {
            let hidden = snapshot.hidesAmounts
            switch family {
            #if os(iOS)
            case .accessoryCircular:
                Gauge(value: min(budget.spentFraction ?? 0, 1)) {
                    Image(systemName: "chart.pie")
                } currentValueLabel: {
                    Text(verbatim: budget.spentFraction.map { Decimal($0).formattedPercent(fractionDigits: 0) } ?? "—")
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bugün harcayabileceğin").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: WidgetFormat.money(budget.perDay, hidden: hidden)).font(.headline).widgetAccentable()
                    Text("\(budget.remainingDays) gün kaldı").font(.caption)
                }
                .monospacedDigit()
            #endif
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bugün harcayabileceğin").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: WidgetFormat.money(budget.perDay, hidden: hidden))
                        .font(.title.weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    if let fraction = budget.spentFraction {
                        ProgressView(value: min(fraction, 1))
                            .tint(fraction > 1 ? .red : .accentColor)
                    }
                    Text("\(budget.remainingDays) gün · kalan \(WidgetFormat.money(budget.remaining, hidden: hidden))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            EmptyWidgetView()
        }
    }
}

// MARK: - Birikim (orta)

struct PortfolioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "portfolio", provider: SnapshotProvider()) { entry in
            PortfolioWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DeepLinkURL.portfolio)
        }
        .configurationDisplayName("Birikim")
        .description("Birikiminin bozdurma değeri ve en büyük üç varlık.")
        .supportedFamilies([.systemMedium])
    }
}

struct PortfolioWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let total = snapshot.portfolioTotal {
            let hidden = snapshot.hidesAmounts
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Birikim").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: WidgetFormat.money(total, hidden: hidden))
                        .font(.title2.weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .widgetAccentable()
                    if let ratio = snapshot.portfolioPnLRatio {
                        Text(verbatim: WidgetFormat.change(ratio)).font(.subheadline.weight(.medium))
                    }
                    Spacer(minLength: 0)
                    if let asOf = snapshot.prices.first?.asOf {
                        AgeText(date: asOf).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.holdings, id: \.name) { holding in
                        HStack {
                            Text(verbatim: holding.name).lineLimit(1)
                            Spacer()
                            Text(verbatim: WidgetFormat.money(holding.value, hidden: hidden))
                        }
                        .font(.caption)
                    }
                }
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyWidgetView()
        }
    }
}

// MARK: - Yaklaşan ödemeler (orta; specs/10 §5)

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "upcoming", provider: SnapshotProvider()) { entry in
            UpcomingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DeepLinkURL.calendar)
        }
        .configurationDisplayName("Yaklaşan ödemeler")
        .description("Önümüzdeki günlerin kira, kart ve abonelik ödemeleri.")
        .supportedFamilies([.systemMedium])
    }
}

struct UpcomingWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let all = snapshot.upcoming {
            let today = Calendar.current.startOfDay(for: entry.date)
            let items = all.filter { $0.date >= today }
            let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
            let week = items.filter { $0.date < weekEnd }.reduce(Decimal(0)) { $0 + $1.amount }
            let hidden = snapshot.hidesAmounts
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Yaklaşan ödemeler").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("7 günde \(WidgetFormat.money(week, hidden: hidden))")
                        .font(.caption.weight(.semibold))
                        .widgetAccentable()
                }
                if items.isEmpty {
                    Text("Önümüzdeki 30 günde bilinen ödeme yok.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.date, format: .dateTime.day().month(.abbreviated))
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .leading)
                            Text(verbatim: item.title).lineLimit(1)
                            if item.isEstimate { Text("tahmini").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            Text(verbatim: WidgetFormat.money(item.amount, hidden: hidden))
                        }
                        .font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyWidgetView()
        }
    }
}

enum DeepLinkURL {
    static let calendar = URL(string: "kumbara://calendar")!
    static let add = URL(string: "kumbara://add")!
    static let scan = URL(string: "kumbara://scan")!
    static let budget = URL(string: "kumbara://budget")!
    static let portfolio = URL(string: "kumbara://portfolio")!
    static let market = URL(string: "kumbara://market")!
}
