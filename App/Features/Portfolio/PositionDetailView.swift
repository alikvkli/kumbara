import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Tek varlığın pozisyonu ve işlemleri (REQ-P3, P4, P6, P7).
struct PositionDetailView: View {
    let asset: AssetCode
    @Query private var records: [AssetTrade]
    @Query private var customAssets: [CustomAsset]
    @Environment(PriceBoard.self) private var board
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.priceKind) private var priceKind: PriceKind = .bid
    @AppStorage(SettingsKey.costMethod) private var costMethod: CostMethod = .averageCost
    @State private var editing: AssetTrade?
    @State private var adding = false
    @State private var pendingDeletion: AssetTrade?
    @State private var deletionError = false
    @State private var editingPrice = false

    init(asset: AssetCode) {
        self.asset = asset
        let id = asset.id
        _records = Query(filter: #Predicate<AssetTrade> { $0.assetID == id }, sort: \AssetTrade.date, order: .reverse)
    }

    private var custom: CustomAsset? {
        guard case .custom(let id) = asset else { return nil }
        return customAssets.first { $0.id.uuidString == id }
    }

    var body: some View {
        let trades = records.compactMap(\.trade)
        let position = try? Position(asset: asset, trades: trades, method: costMethod)
        let quote = board.quote(asset)
        let valuation = position.flatMap { position in quote.map { Valuation(position: position, quote: $0, priceKind: priceKind) } }

        List {
            if let position {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HeroAmount(money: Money(valuation?.value ?? 0, .TRY))
                        if let valuation, position.costBasis > 0 {
                            PnLText(amount: valuation.unrealizedPnL, ratio: valuation.unrealizedReturn).font(.headline)
                        }
                        QuoteProvenance(quote: quote, priceKind: priceKind, freshness: board.freshness(of: asset),
                                        isOffline: board.isOffline)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }

                Section {
                    LabeledContent("Miktar") {
                        Text(verbatim: "\(asset.formatQuantity(position.quantity, locale: locale)) \(asset.unitLabel)")
                    }
                    if let average = position.averageCost {
                        LabeledContent("Ortalama maliyet") { amount(average) }
                    }
                    LabeledContent("Toplam maliyet") { amount(position.costBasis) }
                    if let valuation {
                        LabeledContent { amount(valuation.unitPrice) } label: { Text(priceKind.shortLabel) }
                    }
                    if let quote, let bid = quote.bid, let ask = quote.ask, priceKind != .ask {
                        LabeledContent("Satış fiyatı") { amount(ask) }
                        if let spread = valuation?.spreadCost, spread > 0 {
                            LabeledContent("Makas") { amount(spread) }
                                .help(Text("Bugün alıp hemen bozdursan kaybın: \(Money(ask - bid, .TRY).formatted(locale: locale)) / \(asset.unitLabel)"))
                        }
                    }
                    if position.realizedPnL != 0 {
                        LabeledContent("Gerçekleşen kâr/zarar") {
                            Text(verbatim: Money(position.realizedPnL, .TRY).formatted(locale: locale, sign: .always))
                                .monospacedDigit()
                        }
                    }
                    if let usdNow = board.quote(.fx(.USD))?.price(priceKind), position.isOpen,
                       let benchmark = RealReturn.usdBenchmark(trades: trades, usdTRYNow: usdNow), let valuation {
                        LabeledContent("USD'de tutsaydın") { amount(benchmark) }
                        LabeledContent("USD'ye göre") {
                            PnLText(amount: valuation.value - benchmark, ratio: benchmark > 0 ? (valuation.value - benchmark) / benchmark : nil)
                        }
                    }
                } footer: {
                    if quote?.isDerived == true {
                        Text("Fiyat ons fiyatından türetildi; kuyumcu makası bilinmediği için yaklaşıktır.")
                    }
                }

                if custom != nil {
                    Section {
                        Button("Fiyatı güncelle") { editingPrice = true }
                    } footer: {
                        Text("Bu varlığın fiyatı internetten alınmaz; son girdiğin fiyatla değerlenir.")
                    }
                }
            }

            Section("İşlemler") {
                ForEach(records) { record in
                    Button {
                        editing = record
                    } label: {
                        TradeRow(record: record)
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button("Sil", systemImage: "trash", role: .destructive) { pendingDeletion = record }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: asset.displayName(customName: custom?.name)))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Alım/satım ekle", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { TradeEditor(mode: .create(asset)) }
        .sheet(item: $editing) { TradeEditor(mode: .edit($0)) }
        .sheet(isPresented: $editingPrice) {
            if let custom { CustomAssetEditor(asset: custom) }
        }
        .confirmationDialog("Bu işlem silinsin mi?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: pendingDeletion) { record in
            Button("Sil", role: .destructive) {
                do { try PortfolioStore(context: context).delete(record) } catch { deletionError = true }
            }
        }
        .alert("Silinemedi", isPresented: $deletionError) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Bu alım silinirse sonraki satışlar elde olandan fazla olur. Önce ilgili satışı sil ya da düzenle.")
        }
    }

    private func amount(_ value: Decimal) -> some View {
        Text(verbatim: Money(value, .TRY).formatted(locale: locale)).monospacedDigit()
    }
}

private struct TradeRow: View {
    let record: AssetTrade
    @Environment(\.locale) private var locale

    var body: some View {
        if let trade = record.trade {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trade.side == .buy ? "Alış" : "Satış")
                    Text(verbatim: "\(trade.asset.formatQuantity(trade.quantity, locale: locale)) \(trade.asset.unitLabel) × \(trade.unitPrice.formattedNumber(locale: locale, fractionDigits: 0...2))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: Money(trade.side == .buy ? -trade.grossCost : trade.quantity * trade.unitPrice - trade.fee, .TRY)
                        .formatted(locale: locale, sign: .always))
                        .monospacedDigit()
                    Text(trade.date, format: .dateTime.day().month().year())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
