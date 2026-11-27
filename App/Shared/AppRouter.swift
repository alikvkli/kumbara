import Observation

/// Uygulama bölümleri. iOS'ta sekme, macOS'ta kenar çubuğu öğesi (specs/06 §6.1, §7).
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case summary, ledger, portfolio, budget

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .summary: "square.text.square"
        case .ledger: "list.bullet.rectangle"
        case .portfolio: "chart.line.uptrend.xyaxis"
        case .budget: "chart.pie"
        }
    }
}

/// Gezinme ve global eylemlerin tek kaynağı; menü komutları (macOS) ve araç çubuğu (iOS)
/// aynı durumu değiştirir.
@MainActor
@Observable
final class AppRouter {
    enum Destination: Hashable {
        case section(AppSection)
        case search
        case inbox
    }

    var destination: Destination = .section(.summary)
    var isPresentingQuickAdd = false
    var isImportingReceipt = false

    func show(_ section: AppSection) { destination = .section(section) }
}
