import KumbaraCore
import KumbaraData
import SwiftUI

/// İşlem satırı (iOS listeleri). AX boyutlarında dikey yığına geçer, tutar kesilmez (specs/06 §4).
struct TransactionRow: View {
    let transaction: LedgerTransaction
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(systemImage: transaction.badgeSymbol, color: transaction.badgeColor)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        TransactionTitle(transaction: transaction)
                            .lineLimit(1)
                        if let index = transaction.installmentIndex, let count = transaction.installmentCount {
                            Text(verbatim: "\(index)/\(count)")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                                .accessibilityLabel(Text("\(count) taksitin \(index). taksiti"))
                        }
                    }
                    Text(verbatim: transaction.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                AmountText(transaction.amount, kind: transaction.kind)
            }
        }
        // Planlanmış (gelecek) taksit soluk görünür.
        .opacity(transaction.status == .planned ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct TransactionTitle: View {
    let transaction: LedgerTransaction

    var body: some View {
        if let title = transaction.displayTitle {
            Text(verbatim: title)
        } else {
            Text(transaction.kind.label)
        }
    }
}

extension LedgerTransaction {
    var badgeSymbol: String {
        if kind == .transfer { return "arrow.left.arrow.right" }
        if let category { return category.resolvedSymbol }
        return kind == .income ? "arrow.down.circle" : "circle.dashed"
    }

    var badgeColor: Color {
        if kind == .transfer { return .secondary }
        return category?.color.color ?? .secondary
    }

    /// "Market › Gıda · Nakit" veya transferde "Banka → Nakit".
    var subtitle: String {
        if kind == .transfer {
            return "\(account?.name ?? "—") → \(toAccount?.name ?? "—")"
        }
        return [category?.path, account?.name].compactMap { $0 }.joined(separator: " · ")
    }

    // Tablo sıralama anahtarları (macOS).
    var sortTitle: String { displayTitle ?? "" }
    var sortCategory: String { category?.path ?? "" }
    var sortAccount: String { account?.name ?? "" }
    var sortAmount: Decimal { signedAmount.amount }
}
