import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Özet'te kart satırı: ekstre borcu ve son ödeme tarihi önde (REQ-L8, specs/08 §3.1).
struct CardSummaryRow: View {
    let account: LedgerAccount
    let statement: CardStatement
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            CategoryBadge(systemImage: account.kind.systemImage, color: .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.name)
                Text("Bu dönem \(statement.currentSpending.formatted(locale: locale, fractionDigits: 0)) · kesim \(statement.current.closing.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if statement.remainingDue.isZero {
                    Text("Ödendi").font(.headline).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: statement.remainingDue.formatted(locale: locale, fractionDigits: 0))
                        .font(.headline)
                    DueText(due: statement.last.due)
                        .font(.caption)
                }
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// "son ödeme 25 Kas · 3 gün" — 3 gün ve altı turuncu, geçmişse kırmızı.
struct DueText: View {
    let due: Date
    @Environment(\.calendar) private var calendar

    var body: some View {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day ?? 0
        let date = due.formatted(.dateTime.day().month(.abbreviated))
        if days < 0 {
            Text("son ödeme \(date) geçti").foregroundStyle(.red)
        } else if days == 0 {
            Text("son ödeme bugün").foregroundStyle(.orange)
        } else {
            Text("son ödeme \(date) · \(days) gün").foregroundStyle(days <= 3 ? Color.orange : Color.secondary)
        }
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
                            DueText(due: statement.last.due).font(.subheadline)
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
