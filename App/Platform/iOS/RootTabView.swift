#if os(iOS)
import KumbaraCore
import SwiftUI

/// iOS / iPadOS kök gezinme (specs/06 §6.1).
/// Sekme gezinme içindir; "+" sekmesi yoktur, ekleme araç çubuğundadır (§6.2).
struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.destination) {
            ForEach(AppSection.allCases) { section in
                Tab(section.title, systemImage: section.systemImage, value: AppRouter.Destination.section(section)) {
                    NavigationStack {
                        section.rootView
                            .modifier(QuickActionsToolbar(section: section))
                    }
                }
            }

            Tab(value: AppRouter.Destination.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MarketTickerAccessory()
        }
        .sheet(isPresented: $router.isPresentingMarket) {
            MarketView()
        }
    }
}

/// Her sekmenin araç çubuğundaki ekleme + fiş tarama grubu; sayfa butondan morph eder
/// (specs/06 §5, §6.2).
struct QuickActionsToolbar: ViewModifier {
    let section: AppSection
    @Environment(AppRouter.self) private var router
    @Namespace private var transition
    @State private var showsSettings = false

    /// Ziyaret edilmiş sekmeler hiyerarşide kalır; sayfayı yalnız etkin sekme sunar.
    private var isPresentingQuickAdd: Binding<Bool> {
        Binding(
            get: { router.isPresentingQuickAdd && router.destination == .section(section) },
            set: { router.isPresentingQuickAdd = $0 }
        )
    }

    private var savingsSplit: Binding<SavingsSplitRequest?> {
        Binding(
            get: { router.destination == .section(section) ? router.savingsSplit : nil },
            set: { router.savingsSplit = $0 }
        )
    }

    private var isPresentingTradeEditor: Binding<Bool> {
        Binding(
            get: { router.isPresentingTradeEditor && router.destination == .section(section) },
            set: { router.isPresentingTradeEditor = $0 }
        )
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ayarlar", systemImage: "gearshape") { showsSettings = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    CaptureMenu()
                }
                ToolbarItem(placement: .primaryAction) {
                    if section == .portfolio {
                        Button("Alım/satım ekle", systemImage: "plus") { router.isPresentingTradeEditor = true }
                    } else {
                        Button("Yeni işlem", systemImage: "plus") { router.isPresentingQuickAdd = true }
                    }
                }
                .matchedTransitionSource(id: "quick-add", in: transition)
            }
            .sheet(isPresented: isPresentingQuickAdd, onDismiss: { router.presentPendingSavingsSplit() }) {
                TransactionEditor(mode: .create(.expense))
                    .presentationDetents([.medium, .large])
                    .navigationTransition(.zoom(sourceID: "quick-add", in: transition))
            }
            .sheet(isPresented: isPresentingTradeEditor) {
                TradeEditor(mode: .create(nil))
                    .navigationTransition(.zoom(sourceID: "quick-add", in: transition))
            }
            .sheet(item: savingsSplit) { request in
                SavingsSplitSheet(income: request.income)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack { SettingsView() }
            }
    }
}

/// Alt aksesuar: canlı piyasa şeridi (REQ-X8, specs/06 §6.1). Dokununca piyasa sayfası açılır.
/// Fiyat değişiminde yalnız sistemin rakam geçişi; yanıp sönme yok (specs/06 §5).
struct MarketTickerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(PriceBoard.self) private var board
    @Environment(AppRouter.self) private var router
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.priceKind) private var priceKind: PriceKind = .bid

    /// Fiyatı gelmeyen kalem şeritte "—" diye durmaz, gizlenir; hiçbiri gelmediyse hepsi yer tutucuyla kalır.
    private var assets: [AssetCode] {
        let available = PriceBoard.tickerAssets.filter { board.quote($0) != nil }
        let shown = available.isEmpty ? PriceBoard.tickerAssets : available
        return placement == .inline ? [shown[0]] : shown
    }

    var body: some View {
        Button {
            router.isPresentingMarket = true
        } label: {
            HStack(spacing: 14) {
                ForEach(assets, id: \.self) { asset in
                    TickerItem(title: asset.shortName, quote: board.quote(asset), priceKind: priceKind,
                               isStale: board.freshness(of: asset) == .stale || board.isOffline)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Piyasa fiyatları"))
        .accessibilityHint(Text("Tüm fiyatları göster"))
    }
}

private struct TickerItem: View {
    let title: String
    let quote: Quote?
    let priceKind: PriceKind
    let isStale: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: title).foregroundStyle(.secondary)
            if let quote {
                let value = quote.price(priceKind)
                Text(verbatim: value.formattedNumber(locale: locale, fractionDigits: value >= 1000 ? 0...0 : 2...2))
                    .contentTransition(.numericText(value: (value as NSDecimalNumber).doubleValue))
                    .animation(.default, value: value)
                    .foregroundStyle(isStale ? Color.secondary : Color.primary)
            } else {
                Text(verbatim: "—")
            }
        }
    }
}
#endif
