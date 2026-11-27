import KumbaraData
import SwiftData
import SwiftUI

@main
struct KumbaraApp: App {
    @State private var router = AppRouter()
    private let container: ModelContainer

    init() {
        // UI testleri her çalıştırmada boş, bellek içi bir depoyla başlar.
        // `-demo-data` örnek veriyi yükler (ekran görüntüleri); yalnız bellek içi depoda.
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        do {
            container = try KumbaraContainer.make(inMemory: isUITesting)
            try LedgerSeeder.seedIfNeeded(container.mainContext)
            if isUITesting, arguments.contains("-demo-data") {
                try DemoData.load(into: container.mainContext)
            }
        } catch {
            // TODO(M5): kurtarma ekranı ve dışa aktarma önerisi.
            fatalError("Veri deposu açılamadı: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
        }
        .modelContainer(container)
        #if os(macOS)
        .commands { KumbaraCommands(router: router) }
        #endif

        #if os(macOS)
        Settings {
            NavigationStack {
                SettingsView()
            }
            .frame(minWidth: 480, minHeight: 420)
            .modelContainer(container)
        }
        #endif
    }
}

/// Platforma göre kök gezinme (specs/06 §6.1, §7).
struct RootView: View {
    var body: some View {
        #if os(iOS)
        RootTabView()
        #else
        RootSplitView()
        #endif
    }
}
