import KumbaraCore
import SwiftData
import SwiftUI

/// Piyasa sayfası: tüm altın türleri, metaller ve dövizlerde alış/satış ve fiyatların tazeliği (REQ-M3).
struct MarketView: View {
    @Environment(PriceBoard.self) private var board
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var alertAsset: AssetCode?
    @Query(filter: #Predicate<PriceAlert> { $0.isActive }) private var activeAlerts: [PriceAlert]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PriceBoard.marketAssets, id: \.self) { asset in
                        row(asset)
                            .contextMenu {
                                Button("Alarm kur", systemImage: "bell") { alertAsset = asset }
                            }
                    }
                } header: {
                    HStack {
                        Text("Varlık")
                        Spacer()
                        Text("Alış").frame(width: 84, alignment: .trailing)
                        Text("Satış").frame(width: 84, alignment: .trailing)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        updateStatus
                        Text("Alış: kuyumcunun/bankanın senden aldığı (bozdurma). Satış: sana sattığı. Tahmini fiyatlar ons ve dolar kurundan hesaplanır.")
                    }
                }
            }
            .navigationTitle("Piyasa")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .refreshable { await board.refresh(including: Set(PriceBoard.marketAssets)) }
            .sheet(item: $alertAsset) { asset in PriceAlertEditor(asset: asset) }
            .task {
                // Sayfa açıkken tüm piyasa varlıkları periyodik yenilemeye katılır.
                let token = board.watch(Set(PriceBoard.marketAssets))
                defer { board.unwatch(token) }
                await board.refresh(including: Set(PriceBoard.marketAssets))
                // Görev sayfa kapanınca iptal edilir; o ana kadar izleme sürer.
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            }
        }
    }

    /// En yeni otomatik fiyatın zamanı, sayfada bir kez: her satırda aynı saati tekrarlamak gürültü.
    @ViewBuilder
    private var updateStatus: some View {
        let newest = PriceBoard.marketAssets.compactMap { board.quote($0) }.filter { $0.source != .manual }.map(\.asOf).max()
        if board.isOffline {
            Label {
                if let newest { Text("Bağlantı yok · fiyatlar \(RelativeTimeText.text(for: newest))") } else { Text("Bağlantı yok") }
            } icon: { Image(systemName: "wifi.slash") }
            .foregroundStyle(.orange)
        } else if let newest {
            HStack(spacing: 4) {
                Text("Güncellendi")
                RelativeTimeText(date: newest)
            }
        }
    }

    private func row(_ asset: AssetCode) -> some View {
        let quote = board.quote(asset)
        let freshness = board.freshness(of: asset)
        let isLate = freshness == .stale || freshness == .delayed
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: asset.displayName())
                    if activeAlerts.contains(where: { $0.rule?.asset == asset }) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Alarm kurulu"))
                    }
                }
                // Yalnız olağan dışı satırlar not taşır: tahmini/elle fiyat, ya da diğerlerinden eski fiyat.
                if let quote, quote.originNote != nil || isLate {
                    HStack(spacing: 4) {
                        if let note = quote.originNote { Text(note) }
                        if quote.originNote != nil && isLate { Text(verbatim: "·") }
                        if isLate { RelativeTimeText(date: quote.asOf) }
                    }
                    .font(.caption)
                    .foregroundStyle(isLate ? Color.orange : Color.secondary)
                }
            }
            Spacer()
            price(quote?.bid, asset).frame(width: 84, alignment: .trailing)
            price(quote?.ask, asset).frame(width: 84, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Fiyat henüz gelmediyse ve yenileme sürüyorsa yer tutucu (yükleniyor); "—" yalnız gerçekten
    /// alınamayan fiyat için.
    @ViewBuilder
    private func price(_ value: Decimal?, _ asset: AssetCode) -> some View {
        if let value {
            Text(verbatim: asset.formatPrice(value, locale: locale))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if board.isRefreshing && !board.unavailable.contains(asset) {
            Text(verbatim: "00.000")
                .redacted(reason: .placeholder)
                .accessibilityLabel(Text("Yükleniyor"))
        } else {
            Text(verbatim: "—")
                .accessibilityLabel(Text("Fiyat yok"))
        }
    }
}
