import Combine
import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

@main
struct KumbaraApp: App {
    @State private var router = AppRouter()
    @State private var board: PriceBoard
    @State private var capture: CaptureSession
    @State private var lock = AppLock()
    #if os(macOS)
    @AppStorage("menubar.enabled") private var showsMenuBar = true
    #endif
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
            _ = try? inbox.deposit(data, fileExtension: "jpg")
        }
        return inbox
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            // CaptureEntry ortamdan CaptureSession okur: ortam değerleri yalnız içeriye akar, bu yüzden
            // değiştirici `.environment` çağrılarının İÇİNDE kalmalı (dışında kalırsa açılışta çöker).
            RootView()
                .modifier(CaptureEntry())
                .modifier(AppLockGate())
                .environment(lock)
                .environment(router)
                .environment(board)
                .environment(capture)
        }
        .modelContainer(container)
        #if os(macOS)
        .commands { KumbaraCommands(router: router, capture: capture) }
        #endif
        #if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [board] in
            await board.refresh()
            await MainActor.run { BackgroundRefresh.schedule() }
        }
        #endif

        #if os(macOS)
        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarContent(router: router, capture: capture)
                .environment(board)
        } label: {
            MenuBarLabel().environment(board)
        }

        Settings {
            NavigationStack {
                SettingsView()
            }
            .frame(minWidth: 480, minHeight: 420)
            .modelContainer(container)
            .environment(board)
            .environment(lock)
        }
        #endif
    }
}

/// Platforma göre kök gezinme (specs/06 §6.1, §7).
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(CaptureSession.self) private var capture
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
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
        // Bütçe eşikleri her kayıttan sonra değerlendirilir (REQ-B2); kaydı hangi ekran yapmış olursa olsun.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            BudgetMonitor.shared.check(context)
            WidgetPublisher.publish(context: context, board: board)
        }
        // Widget, Denetim Merkezi ve menü çubuğu bağlantıları: kumbara://add, scan, budget, portfolio, market.
        .onOpenURL { url in DeepLink(url: url)?.open(router: router, capture: capture) }
        // Widget'lar ve menü çubuğu yeni fiyatla güncellenir (specs/09 §4).
        .onChange(of: board.lastSuccess) { _, _ in WidgetPublisher.publish(context: context, board: board) }
        .onAppear { BudgetMonitor.shared.start() }
        // Vadesi gelen tekrarlar taslak olur ve sıradaki vadelerin hatırlatması kurulur (REQ-L7).
        .onChange(of: scenePhase, initial: true) { _, phase in
            #if os(iOS)
            if phase == .background { BackgroundRefresh.schedule() }
            #endif
            guard phase == .active else { return }
            let store = RecurringStore(context: context)
            _ = try? store.generateDrafts()
            if let rules = try? store.rules() { Reminders.schedule(rules) }
            // Tarihi gelen taksitler kesinleşir; kart son ödeme hatırlatmaları kurulur (REQ-L8, L9).
            _ = try? InstallmentStore(context: context).postDue()
            if let accounts = try? context.fetch(FetchDescriptor<LedgerAccount>()) { Reminders.scheduleCardDue(accounts, context: context) }
        }
    }
}

/// Uygulama dışından gelen bağlantılar (specs/09 §4).
enum DeepLink: String {
    case add, scan, budget, portfolio, market

    static let scheme = "kumbara"

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(), let link = DeepLink(rawValue: host) else { return nil }
        self = link
    }

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    @MainActor
    func open(router: AppRouter, capture: CaptureSession) {
        switch self {
        case .add: router.isPresentingQuickAdd = true
        case .scan:
            #if os(iOS)
            capture.requestedSource = .camera
            #else
            capture.requestedSource = .files
            #endif
        case .budget: router.show(.budget)
        case .portfolio: router.show(.portfolio)
        case .market: router.isPresentingMarket = true
        }
    }
}
