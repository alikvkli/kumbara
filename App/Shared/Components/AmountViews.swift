import KumbaraCore
import SwiftUI

/// Satır tutarı: monospaced, gelir `+` ve yeşil, gider `-`, transfer ikincil (specs/06 §3–4, REQ-X7).
struct AmountText: View {
    let money: Money
    let kind: TransactionKind
    @Environment(\.locale) private var locale

    init(_ money: Money, kind: TransactionKind) {
        self.money = money
        self.kind = kind
    }

    var body: some View {
        Text(verbatim: formatted)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .layoutPriority(1)
    }

    private var formatted: String {
        switch kind {
        case .income: money.formatted(locale: locale, sign: .always)
        case .expense: (-money).formatted(locale: locale)
        case .transfer: money.formatted(locale: locale)
        }
    }

    private var color: Color {
        switch kind {
        case .income: .green
        case .expense: .primary
        case .transfer: .secondary
        }
    }
}

/// Kahraman sayı: ekranın en büyük öğesi, küsurat ikincil ve bir boy küçük (specs/06 §4).
struct HeroAmount: View {
    let money: Money
    @Environment(\.locale) private var locale

    var body: some View {
        Text(attributed)
            .font(.largeTitle.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(Text(verbatim: money.formatted(locale: locale)))
    }

    private var attributed: AttributedString {
        let text = money.formatted(locale: locale)
        var result = AttributedString(text)
        if let separator = locale.decimalSeparator, let range = result.range(of: separator, options: .backwards) {
            let fraction = range.lowerBound..<result.endIndex
            result[fraction].foregroundColor = Color.secondary
            result[fraction].font = Font.title.weight(.semibold)
        }
        return result
    }
}

/// Kategori sembolü: yalnız SF Symbol, kategori renginde; arka plan dairesi yok (specs/06 §3, §9).
struct CategoryBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .font(.body)
            .frame(width: 28)
            .accessibilityHidden(true)
    }
}
