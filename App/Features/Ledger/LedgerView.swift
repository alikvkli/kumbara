import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// İşlemler bölümü (T1.4): iOS'ta gün bölümlü `List`, macOS'ta `Table` (specs/06 §2, §7).
struct LedgerView: View {
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: \LedgerAccount.sortIndex) private var accounts: [LedgerAccount]
    @State private var filter = TransactionFilter()

    /// Kesinleşmiş kayıtlar; taslaklar (tekrarlayandan gelen) üstte ayrı bölümde onay bekler (C5).
    private var filtered: [LedgerTransaction] { transactions.filter { $0.status == .posted && filter.matches($0) } }
    private var pending: [LedgerTransaction] { transactions.filter { $0.status == .draft }.sorted { $0.date < $1.date } }

    var body: some View {
        content
            .navigationTitle("İşlemler")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    FilterMenu(filter: $filter, accounts: accounts)
                }
            }
            .overlay {
                if transactions.isEmpty {
                    ContentUnavailableView {
                        Label("İşlem yok", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Eklediğin ve fişten aktardığın işlemler burada listelenir.")
                    } actions: {
                        AddTransactionButton()
                    }
                } else if filtered.isEmpty && pending.isEmpty {
                    ContentUnavailableView("Bu filtreye uyan işlem yok", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        LedgerTable(transactions: filtered)
            .searchable(text: $filter.query, placement: .toolbar, prompt: Text("Satıcı, not, kategori"))
            .safeAreaInset(edge: .top) {
                if !pending.isEmpty {
                    PendingDraftsPanel(drafts: pending)
                }
            }
        #else
        TransactionList(transactions: filtered, pending: pending)
        #endif
    }
}

private struct FilterMenu: View {
    @Binding var filter: TransactionFilter
    let accounts: [LedgerAccount]

    var body: some View {
        Menu {
            Picker("Tür", selection: $filter.kind) {
                Text("Tümü").tag(TransactionKind?.none)
                ForEach(TransactionKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(Optional(kind))
                }
            }
            Picker("Hesap", selection: $filter.accountID) {
                Text("Tüm hesaplar").tag(UUID?.none)
                ForEach(accounts) { account in
                    Text(verbatim: account.name).tag(Optional(account.id))
                }
            }
        } label: {
            Label("Filtre", systemImage: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }
}

/// Gün bölümlü işlem listesi (iOS; arama sekmesinde de kullanılır).
struct TransactionList: View {
    let transactions: [LedgerTransaction]
    var pending: [LedgerTransaction] = []
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @State private var editing: LedgerTransaction?
    @State private var pendingDeletion: LedgerTransaction?

    var body: some View {
        List {
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { draft in
                        PendingDraftRow(draft: draft) { editing = draft }
                    }
                    if pending.count > 1 {
                        Button("Hepsini onayla") {
                            let store = RecurringStore(context: context)
                            for draft in pending { try? store.approve(draft) }
                        }
                    }
                } header: {
                    Text("Onay bekleyenler")
                }
            }
            ForEach(TransactionDay.group(transactions, calendar: calendar)) { day in
                Section {
                    ForEach(day.transactions) { transaction in
                        Button {
                            editing = transaction
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Sil", systemImage: "trash", role: .destructive) {
                                pendingDeletion = transaction
                            }
                        }
                    }
                } header: {
                    DayHeader(day: day)
                }
            }
        }
        // Düz liste + yapışkan gün başlıkları: günde tek kayıt olduğunda inset grouped
        // her satırı ayrı kutuya çevirip "kart yığını" görünümü veriyordu (specs/06 §9).
        .listStyle(.plain)
        .sheet(item: $editing) { transaction in
            TransactionEditor(mode: .edit(transaction))
        }
        .confirmationDialog("Bu işlem silinsin mi?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: pendingDeletion) { transaction in
            Button("Sil", role: .destructive) {
                try? LedgerStore(context: context).delete(transaction)
            }
        }
    }
}

/// Gün başlığı: tarih solda, günün net tutarı sağda (TRY kayıtlar).
private struct DayHeader: View {
    let day: TransactionDay
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide))
            Spacer()
            let net = day.transactions
                .filter { $0.amount.currency == .TRY && $0.status == .posted }
                .map(\.signedAmount)
                .sum(in: .TRY)
            if !net.isZero {
                Text(verbatim: net.formatted(locale: locale, sign: .always))
                    .monospacedDigit()
            }
        }
    }
}

/// Onay bekleyen taslak satırı: dokununca düzenle, sağda tek dokunuşla onayla; kaydırınca atla.
struct PendingDraftRow: View {
    let draft: LedgerTransaction
    let edit: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack {
            Button(action: edit) { TransactionRow(transaction: draft) }
                .tint(.primary)
            Button("Onayla") { try? RecurringStore(context: context).approve(draft) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("draft.approve")
        }
        .swipeActions {
            Button("Atla", systemImage: "forward") { try? RecurringStore(context: context).skip(draft) }
                .tint(.orange)
        }
    }
}

#if os(macOS)
/// macOS: tablo üstünde onay bekleyenler şeridi.
private struct PendingDraftsPanel: View {
    let drafts: [LedgerTransaction]
    @Environment(\.modelContext) private var context
    @State private var editing: LedgerTransaction?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Onay bekleyenler").font(.headline)
                Spacer()
                if drafts.count > 1 {
                    Button("Hepsini onayla") {
                        let store = RecurringStore(context: context)
                        for draft in drafts { try? store.approve(draft) }
                    }
                }
            }
            ForEach(drafts) { draft in
                HStack {
                    Button { editing = draft } label: { TransactionRow(transaction: draft) }
                        .buttonStyle(.plain)
                    Button("Atla") { try? RecurringStore(context: context).skip(draft) }
                    Button("Onayla") { try? RecurringStore(context: context).approve(draft) }
                }
            }
        }
        .padding(12)
        .background(.bar)
        .sheet(item: $editing) { transaction in
            TransactionEditor(mode: .edit(transaction))
        }
    }
}
#endif
