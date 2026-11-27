import Charts
import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Birikim (REQ-P3…P8; T2.5, T2.6). Değer varsayılan olarak bozdurma fiyatıyla (D6);
/// hangi fiyatla hesaplandığı her zaman yazar (C6).
struct PortfolioView: View {
    @Query(sort: \AssetTrade.date) private var records: [AssetTrade]
    @Query private var customAssets: [CustomAsset]
    @Environment(PriceBoard.self) private var board
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.priceKind) private var priceKind: PriceKind = .bid
    @AppStorage(SettingsKey.costMethod) private var costMethod: CostMethod = .averageCost
    @State private var range: ChartRange = .threeMonths

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView {
                    Label("Birikim yok", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Altın, döviz veya kripto alımını kaydet; ortalama maliyetini ve bozdurma değerini burada gör.")
                } actions: {
                    Button("Alım ekle") { router.isPresentingTradeEditor = true }
                }
            } else {
                content
            }
        }
        .navigationTitle("Birikim")
        // Birikim planı hatırlatmasından: alım formu planla dolu (specs/10 §7).
        .sheet(isPresented: Binding(get: { router.planToBuy != nil }, set: { if !$0 { router.planToBuy = nil } })) {
            if let id = router.planToBuy,
               let rule = (try? PlanStore(context: context).plans())?.first(where: { $0.id == id })?.rule {
                TradeEditor(mode: .create(rule.asset),
                            preset: .init(target: rule.target, goalID: rule.goalID, note: String(localized: "Birikim planı")))
            }
        }
        .navigationDestination(for: AssetCode.self) { asset in
            PositionDetailView(asset: asset)
        }
    }

    private var trades: [Trade] { records.compactMap(\.trade) }

    private var positions: [Position] {
        Dictionary(grouping: trades, by: \.asset)
            .compactMap { try? Position(asset: $0.key, trades: $0.value, method: costMethod) }
    }

    private func customName(_ asset: AssetCode) -> String? {
        guard case .custom(let id) = asset else { return nil }
        return customAssets.first { $0.id.uuidString == id }?.name
    }

    private var content: some View {
        let open = positions.filter(\.isOpen)
        let closed = positions.filter { !$0.isOpen && $0.realizedPnL != 0 }
        let rows = open.map { position in
            Holding(position: position,
                    valuation: board.quote(position.asset).map { Valuation(position: position, quote: $0, priceKind: priceKind) })
        }
        .sorted { ($0.valuation?.value ?? 0) > ($1.valuation?.value ?? 0) }
        let priced = rows.compactMap(\.valuation)
        let total = priced.reduce(Decimal(0)) { $0 + $1.value }
        let cost = rows.filter { $0.valuation != nil }.reduce(Decimal(0)) { $0 + $1.position.costBasis }
        let unrealized = total - cost
        let realized = positions.reduce(Decimal(0)) { $0 + $1.realizedPnL }
        let unpricedCount = rows.filter { $0.valuation == nil }.count
        let usdBenchmark = Dictionary(grouping: trades.filter { asset in open.contains { $0.asset == asset.asset } }, by: \.asset)
            .values.reduce(Decimal?(0)) { sum, trades in
                guard let sum, let usd = board.quote(.fx(.USD))?.price(priceKind),
                      let value = RealReturn.usdBenchmark(trades: trades, usdTRYNow: usd) else { return nil }
                return sum + value
            }
        let newest = open.compactMap { board.quote($0.asset) }.filter { $0.source != .manual }.max { $0.asOf < $1.asOf }

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HeroAmount(money: Money(total, .TRY))
                    if cost > 0 {
                        PnLText(amount: unrealized, ratio: unrealized / cost)
                            .font(.headline)
                    }
                    QuoteProvenance(quote: newest, priceKind: priceKind,
                                    freshness: newest.map { Freshness.evaluate(asOf: $0.asOf, now: .now, calendar: .current) },
                                    isOffline: board.isOffline)
                    if let usdBenchmark, usdBenchmark > 0, total > 0 {
                        Text("USD'de tutsaydın \(Money(usdBenchmark, .TRY).formatted(locale: locale, fractionDigits: 0)) · fark \(Money(total - usdBenchmark, .TRY).formatted(locale: locale, sign: .always, fractionDigits: 0))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if realized != 0 {
                        Text("Gerçekleşen kâr/zarar \(Money(realized, .TRY).formatted(locale: locale, sign: .always))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if unpricedCount > 0 {
                        Text("\(unpricedCount) varlığın fiyatı henüz yok; toplama dahil değil.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            Section {
                PortfolioChart(trades: trades, priceKind: priceKind, range: range, current: total)
                Picker("Aralık", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            GoalsSection()
            PlansSection()

            Section("Varlıklar") {
                ForEach(rows) { row in
                    NavigationLink(value: row.position.asset) {
                        PositionRow(position: row.position, valuation: row.valuation,
                                    name: row.position.asset.displayName(customName: customName(row.position.asset)))
                    }
                }
            }

            if !closed.isEmpty {
                Section("Kapanan") {
                    ForEach(closed, id: \.asset) { position in
                        NavigationLink(value: position.asset) {
                            LabeledContent {
                                Text(verbatim: Money(position.realizedPnL, .TRY).formatted(locale: locale, sign: .always))
                                    .monospacedDigit()
                                    .foregroundStyle(position.realizedPnL >= 0 ? Color.green : Color.red)
                            } label: {
                                Label {
                                    Text(verbatim: position.asset.displayName(customName: customName(position.asset)))
                                } icon: {
                                    AssetBadge(asset: position.asset)
                                }
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await board.refresh() }
    }
}

private struct Holding: Identifiable {
    let position: Position
    let valuation: Valuation?
    var id: AssetCode { position.asset }
}

/// Kâr/zarar: işaret + renk + yüzde (REQ-X7: renk tek başına anlam taşımaz).
struct PnLText: View {
    let amount: Decimal
    let ratio: Decimal?
    @Environment(\.locale) private var locale

    var body: some View {
        let arrow = amount > 0 ? "▲" : (amount < 0 ? "▼" : "")
        HStack(spacing: 6) {
            Text(verbatim: "\(arrow) \(Money(amount, .TRY).formatted(locale: locale, sign: .always))")
            if let ratio {
                Text(verbatim: ratio.formattedPercent(locale: locale, fractionDigits: 2, sign: .always))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .foregroundStyle(amount > 0 ? Color.green : (amount < 0 ? Color.red : Color.primary))
    }
}

private struct PositionRow: View {
    let position: Position
    let valuation: Valuation?
    let name: String
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            AssetBadge(asset: position.asset)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: name).lineLimit(1)
                    Spacer(minLength: 8)
                    if let valuation {
                        Text(verbatim: Money(valuation.value, .TRY).formatted(locale: locale, fractionDigits: 0))
                            .monospacedDigit()
                    } else {
                        Text("fiyat yok").foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let valuation {
                        PnLText(amount: valuation.unrealizedPnL, ratio: nil)
                            .font(.footnote)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let quantity = position.asset.formatQuantity(position.quantity, locale: locale)
        let average = position.averageCost.map { position.asset.formatPrice($0, locale: locale) } ?? "—"
        return String(localized: "\(quantity) \(position.asset.unitLabel) · ort. \(average)")
    }
}

/// Grafik açıklaması: renkli düz çizgi = değer, gri kesikli = yatırdığın.
private struct ChartKey: View {
    var body: some View {
        HStack(spacing: 16) {
            key(Text("Değer"), color: .accentColor, dashed: false)
            key(Text("Yatırdığın"), color: .secondary, dashed: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func key(_ title: Text, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 16, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
            .frame(width: 16, height: 8)
            title
        }
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case month, threeMonths, year, all
    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .month: "1A"
        case .threeMonths: "3A"
        case .year: "1Y"
        case .all: "Tümü"
        }
    }

    func start(from now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

/// Portföy değeri grafiği: yerel fiyat kayıtları × o günkü miktar (specs/02 §6).
/// Düz çizgi; gradyan dolgu, gölge yok (specs/06 §9).
private struct PortfolioChart: View {
    let trades: [Trade]
    let priceKind: PriceKind
    let range: ChartRange
    let current: Decimal
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var selected: Date?

    @AppStorage(SettingsKey.costMethod) private var costMethod: CostMethod = .averageCost

    /// Değer ve yatırılan tutar, aynı günler için.
    private var series: (value: [PortfolioHistory.Point], invested: [PortfolioHistory.Point]) {
        let store = PortfolioStore(context: context, calendar: calendar)
        let prices = (try? store.priceHistory(priceKind: priceKind)) ?? [:]
        let start = range.start(from: .now, calendar: calendar) ?? trades.map(\.date).min() ?? .now
        var days = Set(prices.values.flatMap { $0.map(\.date) }.filter { $0 >= calendar.startOfDay(for: start) })
        // Alım günleri de eklenir: yatırılan tutar basamağı alımın yapıldığı güne düşer.
        days.formUnion(trades.map { calendar.startOfDay(for: $0.date) }.filter { $0 >= start })
        var value = PortfolioHistory.series(trades: trades, prices: prices, days: Array(days))
        let valueDays = value.map(\.date)
        var invested = PortfolioHistory.invested(trades: trades, days: valueDays, method: costMethod)
        if current > 0 {
            value.append(.init(date: .now, value: current))
            invested += PortfolioHistory.invested(trades: trades, days: [.now], method: costMethod)
        }
        return (value, invested)
    }

    var body: some View {
        let series = series
        let points = series.value
        if points.count < 2 {
            Text("Grafik, uygulama birkaç gün fiyat kaydettikçe oluşur.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart {
                ForEach(series.invested, id: \.date) { point in
                    LineMark(x: .value("Tarih", point.date),
                             y: .value("Tutar", (point.value as NSDecimalNumber).doubleValue),
                             series: .value("Seri", "invested"))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Color.secondary)
                }
                ForEach(points, id: \.date) { point in
                    LineMark(x: .value("Tarih", point.date),
                             y: .value("Tutar", (point.value as NSDecimalNumber).doubleValue),
                             series: .value("Seri", "value"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor)
                }
                if let selected, let point = points.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                    RuleMark(x: .value("Seçili", point.date))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 2) {
                                Text(verbatim: Money(point.value, .TRY).formatted(locale: locale, fractionDigits: 0))
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                                Text(point.date, format: .dateTime.day().month())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartLegend(.hidden)
            .chartYAxis { AxisMarks(position: .trailing) }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            .accessibilityLabel(Text("Portföy değeri ve yatırılan tutar grafiği"))
            ChartKey()
        }
    }
}
