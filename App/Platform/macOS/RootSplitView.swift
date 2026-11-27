#if os(macOS)
import SwiftUI

/// macOS kök pencere: kenar çubuğu · içerik · denetçi (specs/06 §7).
struct RootSplitView: View {
    @Environment(AppRouter.self) private var router
    @Environment(CaptureSession.self) private var capture
    @State private var showsInspector = false

    var body: some View {
        @Bindable var router = router

        NavigationSplitView {
            List(selection: Binding<AppRouter.Destination?>(
                get: { router.destination },
                set: { if let value = $0 { router.destination = value } }
            )) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(AppRouter.Destination.section(section) as AppRouter.Destination?)
                    }
                }
                Section("Yakalama") {
                    Label("Gelen fişler", systemImage: "tray")
                        .tag(AppRouter.Destination.inbox as AppRouter.Destination?)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            NavigationStack {
                detail
            }
            .inspector(isPresented: $showsInspector) {
                Group {
                    if let id = router.selectedTransactionID {
                        TransactionInspector(id: id)
                    } else {
                        ContentUnavailableView("Seçim yok", systemImage: "sidebar.right",
                                               description: Text("Ayrıntısını görmek için bir kayıt seç."))
                    }
                }
                .inspectorColumnWidth(min: 260, ideal: 300)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if router.destination == .section(.portfolio) {
                    Button("Alım/satım ekle", systemImage: "plus") { router.isPresentingTradeEditor = true }
                } else {
                    Button("Yeni işlem", systemImage: "plus") { router.isPresentingQuickAdd = true }
                }
                Button("Fiş içe aktar", systemImage: "doc.viewfinder") { capture.requestedSource = .files }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Piyasa", systemImage: "chart.bar.xaxis") { router.isPresentingMarket = true }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Ayrıntılar", systemImage: "sidebar.right") { showsInspector.toggle() }
            }
        }
        .sheet(isPresented: $router.isPresentingQuickAdd, onDismiss: { router.presentPendingSavingsSplit() }) {
            TransactionEditor(mode: .create(.expense))
                .frame(minWidth: 460, minHeight: 480)
        }
        .sheet(item: $router.savingsSplit) { request in
            SavingsSplitSheet(income: request.income)
                .frame(minWidth: 440, minHeight: 440)
        }
        .sheet(isPresented: $router.isPresentingTradeEditor) {
            TradeEditor(mode: .create(nil))
        }
        .sheet(isPresented: $router.isPresentingMarket) {
            MarketView()
                .frame(minWidth: 520, minHeight: 560)
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.destination {
        case .section(let section):
            section.rootView
        case .inbox:
            ContentUnavailableView {
                Label("Fiş bırak", systemImage: "tray.and.arrow.down")
            } description: {
                Text("Fiş fotoğrafını, banka ekran görüntüsünü veya e-arşiv PDF'ini bu pencereye sürükle. Okuma tamamen bu Mac'te yapılır.")
            } actions: {
                Button("Dosya seç…") { capture.requestedSource = .files }
            }
            .navigationTitle("Gelen fişler")
        case .search:
            SearchView()
        }
    }
}

/// Menü çubuğu komutları ve klavye kısayolları (specs/06 §7).
struct KumbaraCommands: Commands {
    let router: AppRouter
    let capture: CaptureSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Yeni işlem") { router.isPresentingQuickAdd = true }
                .keyboardShortcut("n")
            Button("Yeni alım/satım") { router.isPresentingTradeEditor = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Fiş aç…") { capture.requestedSource = .files }
                .keyboardShortcut("o")
            Divider()
            Button("Piyasa fiyatları") { router.isPresentingMarket = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { router.show(section) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
        }
    }
}
#endif
