#if os(macOS)
import AppKit
import KumbaraCore
import SwiftUI

/// macOS menü çubuğu öğesi (REQ-X9, specs/09 §4): gram altın canlı; menüde fiyatlar ve hızlı eylemler.
struct MenuBarLabel: View {
    @Environment(PriceBoard.self) private var board
    @Environment(\.locale) private var locale

    var body: some View {
        if let quote = board.quote(.gold(.gram24)) {
            Text(verbatim: "Gram \(quote.price(.bid).formattedNumber(locale: locale, fractionDigits: 0...0))")
                .monospacedDigit()
        } else {
            Image(systemName: "circle.circle")
        }
    }
}

struct MenuBarContent: View {
    let router: AppRouter
    let capture: CaptureSession
    @Environment(PriceBoard.self) private var board
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(WidgetPublisher.priceAssets, id: \.self) { asset in
            if let quote = board.quote(asset) {
                Text(verbatim: "\(asset.shortName)  \(asset.formatPrice(quote.price(.bid), locale: locale)) ₺")
            }
        }
        if let newest = WidgetPublisher.priceAssets.compactMap({ board.quote($0)?.asOf }).max() {
            Text("Güncellendi \(RelativeTimeText.text(for: newest))")
        }
        Divider()
        Button("Harcama ekle…") { bringToFront { router.isPresentingQuickAdd = true } }
            .keyboardShortcut("n")
        Button("Fiş içe aktar…") { bringToFront { capture.requestedSource = .files } }
        Button("Piyasa fiyatları") { bringToFront { router.isPresentingMarket = true } }
        Divider()
        Button("Kumbara'yı aç") { bringToFront {} }
        Button("Fiyatları yenile") { Task { await board.refresh() } }
    }

    /// Ana pencere kapalıysa açılır, öne getirilir; sonra eylem.
    private func bringToFront(_ action: @escaping () -> Void) {
        NSApp.activate()
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            openWindow(id: "main")
        }
        action()
    }
}
#endif
