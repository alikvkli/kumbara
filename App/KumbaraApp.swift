import SwiftUI

@main
struct KumbaraApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
        }
        #if os(macOS)
        .commands { KumbaraCommands(router: router) }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
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
