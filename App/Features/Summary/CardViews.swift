import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Özet'te kart satırı (REQ-L8, specs/08 §3.1): üstte kart ve asıl rakam; altında aynı hizada üç etiketli
/// bilgi. Ekstre borcu varsa: borç, son ödeme, kesim, bu dönem. Ödenmişse: bu dönem, kesim, son ödeme,
/// son ekstre "ödendi".
struct CardSummaryRow: View {
    let account: LedgerAccount
    let statement: CardStatement
    @Environment(\.locale) private var locale

    private var hasDue: Bool { !statement.remainingDue.isZero }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CategoryBadge(systemImage: account.kind.systemImage, color: .secondary)
                Text(verbatim: account.name).font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: (hasDue ? statement.remainingDue : statement.currentSpending).formatted(locale: locale, fractionDigits: 0))
                        .font(.headline)
                    Text(hasDue ? "ekstre borcu" : "bu dönem")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if hasDue {
                    CardFact(title: "Son ödeme") { DueText(due: statement.last.due) }
                    CardFact(title: "Kesim") { DateText(date: statement.current.closing) }
                    CardFact(title: "Bu dönem") {
                        Text(verbatim: statement.currentSpending.formatted(locale: locale, fractionDigits: 0))
                    }
                } else {
                    CardFact(title: "Kesim") { DueText(due: statement.current.closing, style: .plain) }
                    CardFact(title: "Son ödeme") { DateText(date: statement.current.due) }
                    CardFact(title: "Son ekstre") {
                        Label("Ödendi", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .monospacedDigit()
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Kart satırının alt bilgisi: küçük etiket, altında değer; üç sütun eşit genişlikte hizalanır.
private struct CardFact<Value: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            value.font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DateText: View {
    let date: Date
    var body: some View { Text(verbatim: date.formatted(.dateTime.day().month(.abbreviated))) }
}

/// Tarih ve kalan gün: "25 Ara · 28 gün". Son ödeme için 3 gün ve altı turuncu, geçmişse kırmızı
/// ("25 Kas · geçti"); `.plain` (kesim günü) hep ikincil renkte.
struct DueText: View {
    enum Style { case due, plain }
    let due: Date
    var style: Style = .due
    @Environment(\.calendar) private var calendar

    var body: some View {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day ?? 0
        let date = due.formatted(.dateTime.day().month(.abbreviated))
        let color: Color = style == .plain ? .primary : (days < 0 ? .red : days <= 3 ? .orange : .primary)
        Group {
            if days < 0 {
                Text("\(date) · geçti")
            } else if days == 0 {
                Text("bugün")
            } else {
                Text("\(date) · \(days) gün")
            }
        }
        .foregroundStyle(color)
    }
}

/// Kart ayrıntısı: ekstre borcu, bu dönem, gelecek taksitler.
struct CardDetailView: View {
    let account: LedgerAccount
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    // Gözlem: kayıt değişince yeniden hesapla.
    @Query private var transactions: [LedgerTransaction]
    @State private var editing: LedgerTransaction?

    var body: some View {
        let store = InstallmentStore(context: context)
        let statement = try? store.statement(for: account, calendar: calendar)
        let upcoming = store.upcomingInstallments(for: account)
        let period = (account.transactions ?? [])
            .filter { $0.status == .posted && statement?.current.contains($0.date, calendar: calendar) == true }
            .sorted { $0.date > $1.date }

        List {
            if let statement {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ekstre borcu").font(.subheadline).foregroundStyle(.secondary)
                        HeroAmount(money: statement.remainingDue)
                        if statement.remainingDue.isZero {
                            Text("Son ekstre ödendi").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Text("Son ödeme").foregroundStyle(.secondary)
                                DueText(due: statement.last.due)
                            }
                            .font(.subheadline)
                        }
                        if !statement.paidSinceClosing.isZero {
                            Text("Ekstre \(statement.lastStatement.formatted(locale: locale)) · ödenen \(statement.paidSinceClosing.formatted(locale: locale))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .monospacedDigit()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }

                Section {
                    LabeledContent("Harcama") {
                        Text(verbatim: statement.currentSpending.formatted(locale: locale)).monospacedDigit()
                    }
                    LabeledContent("Kesim") {
                        Text(statement.current.closing, format: .dateTime.day().month(.wide))
                    }
                    LabeledContent("Son ödeme") {
                        Text(statement.current.due, format: .dateTime.day().month(.wide))
                    }
                    ForEach(period) { transaction in
                        Button { editing = transaction } label: { TransactionRow(transaction: transaction) }
                            .tint(.primary)
                    }
                } header: {
                    Text("Bu dönem")
                }
            }

            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                } header: {
                    Text("Gelecek taksitler")
                } footer: {
                    let total = upcoming.reduce(Decimal(0)) { $0 + $1.amount.amount }
                    Text("Toplam \(Money(total, account.currency).formatted(locale: locale)); tarihi gelince kendiliğinden kesinleşir.")
                }
            }

            if statement == nil {
                Section {
                    Text("Ekstre dönemini görmek için Ayarlar › Hesaplar'da kartın kesim gününü belirle.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: account.name))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { transaction in
            TransactionEditor(mode: .edit(transaction))
        }
    }
}
