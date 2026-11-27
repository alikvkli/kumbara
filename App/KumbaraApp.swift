import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

@main
struct KumbaraApp: App {
    @State private var router = AppRouter()
    @State private var board: PriceBoard
    @State private var capture: CaptureSession
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
        _board = State(initialValue: PriceBoard(container: container))
        _capture = State(initialValue: CaptureSession(inbox: Self.makeInbox(arguments: arguments)))
    }

    /// UI testlerinde App Group yerine boş bir geçici klasör kullanılır; `-demo-inbox` örnek fişi
    /// paylaş uzantısı yazmış gibi bırakır (uçtan uca REQ-C2 testi).
    private static func makeInbox(arguments: [String]) -> CaptureInbox? {
        guard arguments.contains("-ui-testing") else { return CaptureInbox.shared() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UITestInbox", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let inbox = CaptureInbox(directory: directory)
        if arguments.contains("-demo-inbox"),
           let url = Bundle.main.url(forResource: "DemoReceipt", withExtension: "jpg"),
           let data = try? Data(contentsOf: url) {
            try? inbox.deposit(data, fileExtension: "jpg")
        }
        return inbox
    }

    var body: some Scene {
        WindowGroup {
            // CaptureEntry ortamdan CaptureSession okur: ortam değerleri yalnız içeriye akar, bu yüzden
            // değiştirici `.environment` çağrılarının İÇİNDE kalmalı (dışında kalırsa açılışta çöker).
            RootView()
                .modifier(CaptureEntry())
                .environment(router)
                .environment(board)
                .environment(capture)
        }
        .modelContainer(container)
        #if os(macOS)
        .commands { KumbaraCommands(router: router, capture: capture) }
        #endif

        #if os(macOS)
        Settings {
            NavigationStack {
                SettingsView()
            }
            .frame(minWidth: 480, minHeight: 420)
            .modelContainer(container)
            .environment(board)
        }
        #endif
    }
}

/// Platforma göre kök gezinme (specs/06 §6.1, §7).
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PriceBoard.self) private var board

    var body: some View {
        Group {
            #if os(iOS)
            RootTabView()
            #else
            RootSplitView()
            #endif
        }
        // Ön plandayken fiyatlar 60 sn'de bir yenilenir; arka plana geçince görev iptal olur (REQ-M2).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await board.runWhileActive()
        }
    }
}
