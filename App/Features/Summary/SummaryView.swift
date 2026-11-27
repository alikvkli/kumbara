import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Aylık özet (REQ-B3, B4; T1.6). Rakam kahramandır; kart yok, sistem listesi (specs/06 §2, §10).
struct SummaryView: View {
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(AppRouter.self) private var router
    @State private var selectedMonth: LedgerMonth?
    @Environment(\.modelContext) private var context
    @Query private var budgets: [Budget]
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]

    /// Özet ana para biriminde; diğer para birimleri ayrıca belirtilir (kur desteği M2).
    private let currency = CurrencyCode.TRY

    private var month: LedgerMonth { selectedMonth ?? LedgerMonth(containing: .now, calendar: calendar) }

    /// Dağılım üst kategoriler üzerinden: alt kategori harcaması üstüne toplanır.
    private var entries: [LedgerEntry] {
        transactions.map { transaction in
            var entry = transaction.entry
            entry.categoryID = transaction.category?.parent?.id ?? transaction.category?.id
            return entry
        }
    }

    private var categoriesByID: [UUID: LedgerCategory] {
        var result: [UUID: LedgerCategory] = [:]
        for transaction in transactions {
            guard let category = transaction.category else { continue }
            let top = category.parent ?? category
            result[top.id] = top
        }
        return result
    }

    var body: some View {
        Group {
            if transactions.isEmpty {
                ContentUnavailableView {
                    Label("Henüz işlem yok", systemImage: "square.text.square")
                } description: {
                    Text("İlk gelir ya da giderini ekle; aylık özet burada görünecek.")
                } actions: {
                    AddTransactionButton()
                }
            } else {
                summaryList
            }
        }
        .navigationTitle("Özet")
    }

    private var summaryList: some View {
        let entries = entries
        let summary = MonthlySummary(entries: entries, month: month, currency: currency, calendar: calendar)
        let previous = MonthlySummary(entries: entries, month: month.previous, currency: currency, calendar: calendar)
        // Genel bütçe varsa günlük hak bütçenin kalanından, yoksa ayın netinden (REQ-B4).
        let overall = budgets.contains(where: \.isOverall)
            ? (try? BudgetStore(context: context).statuses(for: month, calendar: calendar))?.first { $0.categoryID == nil }
            : nil
        let allowance = DailyAllowance(remaining: overall?.remaining ?? summary.net, month: month, today: .now, calendar: calendar)
        let categories = categoriesByID

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    MonthMenu(month: month, selection: $selectedMonth)
                    HeroAmount(money: summary.net)
                    Text("Gelir \(summary.income.formatted(locale: locale)) · Gider \(summary.expense.formatted(locale: locale))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let allowance {
                        Text("\(allowance.remainingDays) gün kaldı · günlük \(allowance.perDay.formatted(locale: locale))")
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                    if let change = summary.expenseChange(from: previous) {
                        Text("Geçen aya göre gider \(change.formattedPercent(locale: locale, fractionDigits: 0, sign: .always))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            } footer: {
                if !summary.otherCurrencies.isEmpty {
                    let codes = summary.otherCurrencies.map(\.rawValue).sorted().joined(separator: ", ")
                    Text("\(codes) cinsinden kayıtlar bu toplama dahil değil.")
                }
            }

            let cards = accounts.compactMap { account in
                (try? InstallmentStore(context: context).statement(for: account, calendar: calendar)).map { (account, $0) }
            }
            if !cards.isEmpty {
                Section("Kartlar") {
                    ForEach(cards, id: \.0.id) { card in
                        NavigationLink { CardDetailView(account: card.0) } label: {
                            CardSummaryRow(account: card.0, statement: card.1)
                        }
                    }
                }
            }

            if !summary.expenseByCategory.isEmpty {
                Section("Harcama dağılımı") {
                    ForEach(summary.expenseByCategory.prefix(6), id: \.categoryID) { item in
                        CategoryShareRow(item: item, category: item.categoryID.flatMap { categories[$0] })
                    }
                }
            }

            Section {
                ForEach(transactions.prefix(5)) { transaction in
                    TransactionRow(transaction: transaction)
                }
                Button("Tüm işlemler") { router.show(.ledger) }
            } header: {
                Text("Son işlemler")
            }
        }
    }
}

struct MonthMenu: View {
    let month: LedgerMonth
    @Binding var selection: LedgerMonth?
    @Environment(\.calendar) private var calendar

    private var recentMonths: [LedgerMonth] {
        let current = LedgerMonth(containing: .now, calendar: calendar)
        return Array(sequence(first: current) { $0.previous }.prefix(12))
    }

    var body: some View {
        Menu {
            Picker("Ay", selection: Binding(get: { month }, set: { selection = $0 })) {
                ForEach(recentMonths, id: \.self) { item in
                    Text(title(item)).tag(item)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title(month))
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
            }
            .font(.headline)
        }
        .tint(.primary)
    }

    private func title(_ month: LedgerMonth) -> String {
        month.interval(in: calendar).start.formatted(.dateTime.month(.wide).year())
    }
}

private struct CategoryShareRow: View {
    let item: MonthlySummary.CategoryTotal
    let category: LedgerCategory?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CategoryBadge(systemImage: category?.resolvedSymbol ?? "circle.dashed",
                              color: category?.color.color ?? .secondary)
                if let category {
                    Text(verbatim: category.name)
                } else {
                    Text("Kategorisiz")
                }
                Spacer()
                Text(verbatim: item.total.formatted(locale: locale))
                    .monospacedDigit()
                Text(verbatim: item.share.formattedPercent(locale: locale, fractionDigits: 0))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            ProgressView(value: (item.share as NSDecimalNumber).doubleValue)
                .tint(category?.color.color ?? .secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
