import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Piyasa sayfası: altın türleri ve dövizlerde alış/satış ve fiyatların tazeliği (REQ-M3).
struct MarketView: View {
    @Environment(PriceBoard.self) private var board
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var alertAsset: AssetCode?
    @AppStorage("market.group") private var group: MarketGroup = .gold
    @Query(filter: #Predicate<PriceAlert> { $0.isActive }) private var activeAlerts: [PriceAlert]

    var body: some View {
        NavigationStack {
            List {
                // Altın ve döviz ayrı: aynı tabloda karışınca aranan satır kayboluyor.
                Section {
                    Picker("Grup", selection: $group) {
                        ForEach(MarketGroup.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    ForEach(shownAssets, id: \.self) { asset in
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
                        Text(group.footnote)
                    }
                }
                // Fiyatı gelmeyenler tek satırda: tablo boyunca "—" dizmek yerine ne olduğunu söyle.
                if !missingAssets.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Şu an alınamadı", systemImage: "exclamationmark.icloud")
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: missingAssets.map { $0.displayName() }.formatted(.list(type: .and)))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        Button("Yeniden dene", systemImage: "arrow.clockwise") {
                            Task { await board.refresh(including: Set(PriceBoard.marketAssets)) }
                        }
                        .disabled(board.isRefreshing)
                    } footer: {
                        Text("Kaynak bu fiyatları şu an vermiyor. Sayfa açıkken kendiliğinden tekrar denenir.")
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

    /// Fiyatı olan ya da hâlâ yüklenen varlıklar tabloda; gerçekten alınamayanlar ayrı bölümde.
    private var groupAssets: [AssetCode] { PriceBoard.marketAssets.filter { MarketGroup(asset: $0) == group } }
    private var shownAssets: [AssetCode] { groupAssets.filter { !isMissing($0) } }
    private var missingAssets: [AssetCode] { groupAssets.filter(isMissing) }
    private func isMissing(_ asset: AssetCode) -> Bool {
        // Yalnız son yenilemede kaynağın vermediği varlık; henüz denenmemiş olan tabloda yer tutucuyla kalır.
        board.quote(asset) == nil && board.unavailable.contains(asset)
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

/// Piyasa sayfasının grupları. Değerli metaller (gümüş, platin, paladyum) piyasa sayfasında gösterilmez.
enum MarketGroup: String, CaseIterable, Identifiable {
    case gold, fx

    var id: Self { self }

    init?(asset: AssetCode) {
        switch asset {
        case .gold: self = .gold
        case .fx: self = .fx
        default: return nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .gold: "Altın"
        case .fx: "Döviz"
        }
    }

    var footnote: LocalizedStringKey {
        switch self {
        case .gold: "Alış: kuyumcunun senden aldığı (bozdurma). Satış: sana sattığı. Tahmini fiyatlar ons ve dolar kurundan hesaplanır."
        case .fx: "Alış: bankanın senden aldığı. Satış: sana sattığı."
        }
    }
}
