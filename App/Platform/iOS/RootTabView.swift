#if os(iOS)
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

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ayarlar", systemImage: "gearshape") { showsSettings = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Fiş tara", systemImage: "doc.viewfinder") { router.isImportingReceipt = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Yeni işlem", systemImage: "plus") { router.isPresentingQuickAdd = true }
                }
                .matchedTransitionSource(id: "quick-add", in: transition)
            }
            .sheet(isPresented: isPresentingQuickAdd) {
                TransactionEditor(mode: .create(.expense))
                    .presentationDetents([.medium, .large])
                    .navigationTransition(.zoom(sourceID: "quick-add", in: transition))
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack { SettingsView() }
            }
    }
}

/// Alt aksesuar: canlı piyasa şeridi (REQ-X8, specs/06 §6.1). Veri M2'de (T2.0) bağlanır.
struct MarketTickerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 12) {
            TickerItem(title: "Gram", value: nil)
            if placement != .inline {
                TickerItem(title: "USD", value: nil)
                TickerItem(title: "EUR", value: nil)
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

private struct TickerItem: View {
    let title: LocalizedStringKey
    let value: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(verbatim: value ?? "—")
        }
    }
}
#endif
