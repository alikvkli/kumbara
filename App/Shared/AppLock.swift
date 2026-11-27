import LocalAuthentication
import SwiftData
import Observation
import SwiftUI

/// Uygulama kilidi (REQ-X3, specs/09 §2). Face ID / Touch ID, yedek olarak cihaz parolası
/// (`deviceOwnerAuthentication`); uygulamanın ayrı parolası yok (R4).
@MainActor
@Observable
final class AppLock {
    enum Timeout: Int, CaseIterable, Identifiable {
        case immediately = 0, oneMinute = 60, fiveMinutes = 300
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .immediately: "Hemen"
            case .oneMinute: "1 dakika sonra"
            case .fiveMinutes: "5 dakika sonra"
            }
        }
    }

    static let enabledKey = "lock.enabled"
    static let timeoutKey = "lock.timeout"
    static let hidePreviewKey = "lock.hidePreview"

    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private var backgroundedAt: Date?
    private let defaults: UserDefaults

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var timeout: Timeout { Timeout(rawValue: defaults.integer(forKey: Self.timeoutKey)) ?? .immediately }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.hidePreviewKey: true])
        // UI testlerinde kilit yok.
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        isLocked = !uiTesting && defaults.bool(forKey: Self.enabledKey)
    }

    /// Cihazda biyometri ya da parola var mı; yoksa kilit açılamaz, ayar sunulmaz.
    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: LocalizedStringKey {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Cihaz parolası"
        }
    }

    func didEnterBackground(now: Date = .now) {
        guard isEnabled else { return }
        backgroundedAt = now
        if timeout == .immediately { isLocked = true }
    }

    func willEnterForeground(now: Date = .now) {
        guard isEnabled, let backgroundedAt else { return }
        if now.timeIntervalSince(backgroundedAt) >= TimeInterval(timeout.rawValue) { isLocked = true }
        self.backgroundedAt = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Parolayı kullan")
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                localizedReason: String(localized: "Kumbara'nın kilidini aç")) {
                isLocked = false
            }
        } catch {
            // Vazgeçildi ya da başarısız: kilit ekranı kalır, "Kilidi aç" yeniden denenebilir.
        }
    }

    /// Kilidi açmak için önce kimlik doğrulanır (kilidi kapatmak da bir güvenlik değişikliği).
    func setEnabled(_ enabled: Bool) async -> Bool {
        let context = LAContext()
        do {
            let reason = enabled ? String(localized: "Kilidi aç") : String(localized: "Kilidi kapat")
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { return false }
        } catch {
            return false
        }
        defaults.set(enabled, forKey: Self.enabledKey)
        isLocked = false
        return true
    }

    func setTimeout(_ timeout: Timeout) {
        defaults.set(timeout.rawValue, forKey: Self.timeoutKey)
    }
}

/// Kilit ve uygulama değiştirici önizlemesi için kök değiştirici. Ön planda değilken içerik
/// bulanıklaşır ("Önizlemede tutarları gizle"); kilitliyse kilit ekranı üstte durur.
struct AppLockGate: ViewModifier {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.hidePreviewKey) private var hidePreview = true
    @State private var didAutoPrompt = false

    func body(content: Content) -> some View {
        // Uygulama değiştirici önizlemesi yalnız iOS'ta; macOS'ta pencere arka plandayken de görünür kalır.
        #if os(iOS)
        let covered = lock.isLocked || (hidePreview && scenePhase != .active)
        #else
        let covered = lock.isLocked
        #endif
        content
            .blur(radius: covered ? 24 : 0)
            .allowsHitTesting(!lock.isLocked)
            .accessibilityHidden(lock.isLocked)
            .overlay {
                if lock.isLocked {
                    LockScreen()
                } else if covered {
                    Color.clear.background(.regularMaterial).ignoresSafeArea()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: lock.didEnterBackground()
                case .active:
                    lock.willEnterForeground()
                    autoPrompt()
                default: break
                }
            }
            .onAppear(perform: autoPrompt)
    }

    /// Açılışta ve her dönüşte bir kez Face ID istenir; vazgeçilirse düğme kalır.
    private func autoPrompt() {
        guard lock.isLocked, scenePhase == .active else { didAutoPrompt = false; return }
        guard !didAutoPrompt else { return }
        didAutoPrompt = true
        Task { await lock.unlock(); didAutoPrompt = false }
    }
}

private struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Kumbara kilitli").font(.title2.weight(.semibold))
            Button {
                Task { await lock.unlock() }
            } label: {
                Text("Kilidi aç").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lock.isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
    }
}

/// Ayarlar › Kilit.
struct LockSettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(PriceBoard.self) private var board
    @Environment(\.modelContext) private var context
    @AppStorage(AppLock.hidePreviewKey) private var hidePreview = true
    @AppStorage(WidgetPublisher.hideAmountsKey) private var hideWidgetAmounts = false
    @State private var enabled = false
    @State private var timeout: AppLock.Timeout = .immediately

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { newValue in
                    Task { if await lock.setEnabled(newValue) { enabled = newValue } }
                })) {
                    Text(AppLock.biometryName)
                }
                .disabled(!AppLock.canAuthenticate)
                if enabled {
                    Picker("Kilitlenme", selection: $timeout) {
                        ForEach(AppLock.Timeout.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: timeout) { _, value in lock.setTimeout(value) }
                }
            } footer: {
                if AppLock.canAuthenticate {
                    Text("Açıkken Kumbara, seçtiğin süre geçince kilidi sorar. Yüzün ya da parmak izin tanınmazsa cihaz parolası kullanılır; Kumbara'nın ayrı bir parolası yok.")
                } else {
                    Text("Bu cihazda parola ya da Face ID tanımlı değil; kilit kullanılamıyor.")
                }
            }
            Section {
                Toggle("Widget'larda tutarları gizle", isOn: $hideWidgetAmounts)
                    .onChange(of: hideWidgetAmounts) { _, _ in WidgetPublisher.publish(context: context, board: board) }
            } footer: {
                Text("Ana ekran ve kilit ekranı widget'larında bütçe ve birikim tutarları yerine ••• görünür; piyasa fiyatları görünmeye devam eder.")
            }
            #if os(iOS)
            Section {
                Toggle("Önizlemede tutarları gizle", isOn: $hidePreview)
            } footer: {
                Text("Uygulama değiştiricide Kumbara bulanık görünür.")
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("Kilit")
        .onAppear {
            enabled = lock.isEnabled
            timeout = lock.timeout
        }
    }
}
