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
                VStack(alignment: .leading, spacing: 16) {
                    MonthMenu(month: month, selection: $selectedMonth)
                    MonthHeader(summary: summary, change: summary.expenseChange(from: previous), isCurrentMonth: allowance != nil)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 12, trailing: 4))
            } footer: {
                if !summary.otherCurrencies.isEmpty {
                    let codes = summary.otherCurrencies.map(\.rawValue).sorted().joined(separator: ", ")
                    Text("\(codes) cinsinden kayıtlar bu toplama dahil değil.")
                }
            }

            if let allowance {
                Section {
                    AllowanceRow(allowance: allowance, hasBudget: overall != nil) { router.show(.budget) }
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
                // Yalnız gerçekleşmiş kayıtlar: planlanmış gelecek taksitler ve onay bekleyen taslaklar burada değil.
                ForEach(Array(transactions.filter { $0.status == .posted }.prefix(5))) { transaction in
                    TransactionRow(transaction: transaction)
                }
                Button("Tüm işlemler") { router.show(.ledger) }
            } header: {
                Text("Son işlemler")
            }
        }
    }
}

/// Ayın özeti: kalan tutar kahraman; altında gelirin ne kadarının harcandığını gösteren tek çubuk ve
/// iki etiketli sütun (gelir / gider). Satır içi "·" dizileri yerine her rakamın kendi etiketi var.
private struct MonthHeader: View {
    let summary: MonthlySummary
    let change: Decimal?
    let isCurrentMonth: Bool
    @Environment(\.locale) private var locale

    private var spentShare: Double? {
        guard summary.income.amount > 0 else { return nil }
        return (summary.expense.amount / summary.income.amount as NSDecimalNumber).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if summary.net.isNegative {
                        Text("Gelirden fazla harcandı")
                    } else {
                        Text(isCurrentMonth ? "Bu ay kalan" : "Ay sonunda kalan")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HeroAmount(money: summary.net)
            }
            if let spentShare {
                SpendBar(share: spentShare)
                    .accessibilityLabel(Text("Gelirin \(Decimal(spentShare).formattedPercent(locale: locale, fractionDigits: 0)) kadarı harcandı"))
            }
            HStack(alignment: .top) {
                figure(title: "Gelir", value: summary.income, note: nil)
                figure(title: "Gider", value: summary.expense, note: changeNote)
            }
        }
    }

    private var changeNote: Text? {
        guard let change, change != 0 else { return nil }
        let percent = (change < 0 ? -change : change).formattedPercent(locale: locale, fractionDigits: 0)
        return change > 0 ? Text("geçen aydan \(percent) fazla") : Text("geçen aydan \(percent) az")
    }

    private func figure(title: LocalizedStringKey, value: Money, note: Text?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: value.formatted(locale: locale, fractionDigits: 0))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            if let note { note.font(.footnote).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Gelirin harcanan payı. Gelir aşılırsa çubuk dolu ve kırmızı (renk anlam taşır).
private struct SpendBar: View {
    let share: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(share > 1 ? Color.red : Color.accentColor)
                    .frame(width: proxy.size.width * min(max(share, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

/// "Bugün harcayabileceğin": genel bütçe varsa ondan, yoksa ayın netinden; dokununca Bütçe.
private struct AllowanceRow: View {
    let allowance: DailyAllowance
    let hasBudget: Bool
    let open: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: open) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bugün harcayabileceğin").font(.subheadline).foregroundStyle(.secondary)
                    Text(verbatim: allowance.perDay.formatted(locale: locale, fractionDigits: 0))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(allowance.remainingDays) gün kaldı").font(.subheadline).foregroundStyle(.secondary)
                    Text(hasBudget ? "bütçene göre" : "kalan tutara göre").font(.footnote).foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
