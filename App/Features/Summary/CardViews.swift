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
            CardFacts(statement: statement, cardID: account.id)
        }
        .monospacedDigit()
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Kartın üç etiketli bilgisi, eşit sütunlarda; Özet satırında ve kart ayrıntısında aynı.
/// Borç varsa: Son ödeme · Kesim · Bu dönem. Ödenmişse: Kesim · Son ödeme · Son ekstre ödendi.
/// Tarih tek satırda; kalan gün altında ayrı satır (sütun daralınca kırılmasın diye).
struct CardFacts: View {
    let statement: CardStatement
    var cardID: UUID?
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    /// Son ödeme günü geçti ama asgari ödendi: gecikme yok, kalan borç faiziyle devreder (specs/11).
    private var minimumPaidAfterDue: Bool {
        guard calendar.startOfDay(for: statement.last.due) < calendar.startOfDay(for: .now) else { return false }
        let rule = cardID.map { CardInterestSettings.load($0).rule } ?? .standard
        return statement.paidSinceClosing.amount >= CardInterest.minimum(balance: statement.lastStatement.amount, rule: rule)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !statement.remainingDue.isZero {
                CardFact(title: "Son ödeme", value: date(statement.last.due),
                         detail: minimumPaidAfterDue
                             ? AnyView(Text("asgari ödendi").foregroundStyle(.secondary))
                             : AnyView(DaysLeft(date: statement.last.due, urgent: true)))
                CardFact(title: "Kesim", value: date(statement.current.closing), detail: nil)
                CardFact(title: "Bu dönem",
                         value: Text(verbatim: statement.currentSpending.formatted(locale: locale, fractionDigits: 0)), detail: nil)
            } else {
                CardFact(title: "Kesim", value: date(statement.current.closing), detail: AnyView(DaysLeft(date: statement.current.closing, urgent: false)))
                CardFact(title: "Son ödeme", value: date(statement.current.due), detail: nil)
                CardFact(title: "Son ekstre", value: Text("\(Image(systemName: "checkmark.circle.fill")) Ödendi"),
                         detail: statement.lastStatement.isZero ? nil
                             : AnyView(Text(verbatim: statement.lastStatement.formatted(locale: locale, fractionDigits: 0))
                                .foregroundStyle(.secondary)))
            }
        }
        .monospacedDigit()
    }

    private func date(_ date: Date) -> Text { Text(verbatim: date.formatted(.dateTime.day().month(.abbreviated))) }
}

private struct CardFact: View {
    let title: LocalizedStringKey
    let value: Text
    let detail: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            value.font(.subheadline.weight(.medium)).lineLimit(1)
            if let detail { detail.font(.caption) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "18 gün" · "bugün" · "geçti". Son ödemede 3 gün ve altı turuncu, geçmişse kırmızı (renk anlam taşır).
struct DaysLeft: View {
    let date: Date
    let urgent: Bool
    @Environment(\.calendar) private var calendar

    var body: some View {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
        let color: Color = !urgent ? .secondary : days < 0 ? .red : days <= 3 ? .orange : .secondary
        Group {
            if days < 0 { Text("geçti") } else if days == 0 { Text("bugün") } else { Text("\(days) gün") }
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
                let hasDue = !statement.remainingDue.isZero
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasDue ? "Ekstre borcu" : "Bu dönem").font(.subheadline).foregroundStyle(.secondary)
                            HeroAmount(money: hasDue ? statement.remainingDue : statement.currentSpending)
                            // Kısmi ödeme: ne kadarı ödendi. Tam ödenmişse "Son ekstre" sütunu söylüyor, tekrar yok.
                            if hasDue, !statement.paidSinceClosing.isZero {
                                Text("Ekstre \(statement.lastStatement.formatted(locale: locale)) · ödenen \(statement.paidSinceClosing.formatted(locale: locale))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        CardFacts(statement: statement, cardID: account.id)
                    }
                    .monospacedDigit()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }

                // Faiz hesabı yalnız TL kartta ve ödenmemiş ekstre varken (specs/11 §4).
                if hasDue, account.currency == .TRY {
                    Section {
                        NavigationLink {
                            CardInterestView(cardID: account.id, statement: statement.lastStatement.amount,
                                             paid: statement.paidSinceClosing.amount, due: statement.last.due)
                        } label: {
                            CardInterestLinkLabel(cardID: account.id, statement: statement)
                        }
                    }
                }

                if !period.isEmpty {
                    Section("Bu dönemin işlemleri") {
                        ForEach(period) { transaction in
                            Button { editing = transaction } label: { TransactionRow(transaction: transaction) }
                                .tint(.primary)
                        }
                    }
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
