#if os(macOS)
import SwiftUI

/// macOS kök pencere: kenar çubuğu · içerik · denetçi (specs/06 §7).
struct RootSplitView: View {
    @Environment(AppRouter.self) private var router
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
                Button("Yeni işlem", systemImage: "plus") { router.isPresentingQuickAdd = true }
                Button("Fiş içe aktar", systemImage: "doc.viewfinder") { router.isImportingReceipt = true }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Denetçi", systemImage: "sidebar.right") { showsInspector.toggle() }
            }
        }
        .sheet(isPresented: $router.isPresentingQuickAdd) {
            TransactionEditor(mode: .create(.expense))
                .frame(minWidth: 460, minHeight: 480)
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
                Label("Gelen kutusu boş", systemImage: "tray")
            } description: {
                Text("Fiş fotoğrafını, ekran görüntüsünü veya PDF'i bu pencereye sürükle.")
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

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Yeni işlem") { router.isPresentingQuickAdd = true }
                .keyboardShortcut("n")
            Button("Fiş aç…") { router.isImportingReceipt = true }
                .keyboardShortcut("o")
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
