import KumbaraCore
import SwiftUI

/// Piyasa sayfası: tüm altın türleri, metaller ve dövizlerde alış/satış, kaynak ve zaman (REQ-M3).
struct MarketView: View {
    @Environment(PriceBoard.self) private var board
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PriceBoard.marketAssets, id: \.self) { asset in
                        row(asset)
                    }
                } header: {
                    HStack {
                        Text("Varlık")
                        Spacer()
                        Text("Alış").frame(width: 84, alignment: .trailing)
                        Text("Satış").frame(width: 84, alignment: .trailing)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let attempt = board.lastAttempt {
                            Text("Son deneme \(attempt.formatted(date: .omitted, time: .shortened))")
                        }
                        Text("Alış: kuyumcunun/bankanın senden aldığı (bozdurma). Satış: sana sattığı. Kaynaklar: Truncgil, TCMB, gold-api, ECB, CoinGecko.")
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

    private func row(_ asset: AssetCode) -> some View {
        let quote = board.quote(asset)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: asset.displayName())
                if let quote {
                    Text(verbatim: "\(quote.source.label)\(quote.isDerived ? " ≈" : "") · \(quote.asOf.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(board.freshness(of: asset) == .stale ? Color.orange : Color.secondary)
                }
            }
            Spacer()
            price(quote?.bid, asset).frame(width: 84, alignment: .trailing)
            price(quote?.ask, asset).frame(width: 84, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func price(_ value: Decimal?, _ asset: AssetCode) -> some View {
        Text(verbatim: value.map { asset.formatPrice($0, locale: locale) } ?? "—")
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
