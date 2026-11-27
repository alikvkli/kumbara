#if os(macOS)
import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// macOS işlem tablosu: sıralanabilir sütunlar, çoklu seçim, sağ tık menüsü, ⌫ ile silme (specs/06 §7).
struct LedgerTable: View {
    let transactions: [LedgerTransaction]
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @State private var sortOrder = [KeyPathComparator(\LedgerTransaction.date, order: .reverse)]
    @State private var selection = Set<LedgerTransaction.ID>()
    @State private var editing: LedgerTransaction?
    @State private var pendingDeletion: [LedgerTransaction] = []

    private var rows: [LedgerTransaction] { transactions.sorted(using: sortOrder) }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Tarih", value: \.date) { transaction in
                Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("Açıklama", value: \.sortTitle) { transaction in
                Label {
                    TransactionTitle(transaction: transaction)
                } icon: {
                    CategoryBadge(systemImage: transaction.badgeSymbol, color: transaction.badgeColor)
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Kategori", value: \.sortCategory) { transaction in
                Text(verbatim: transaction.kind == .transfer ? transaction.subtitle : (transaction.category?.path ?? "—"))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Hesap", value: \.sortAccount) { transaction in
                Text(verbatim: transaction.account?.name ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Tutar", value: \.sortAmount) { transaction in
                AmountText(transaction.amount, kind: transaction.kind)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 100, ideal: 130)
        }
        .contextMenu(forSelectionType: LedgerTransaction.ID.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button("Düzenle…") { editing = transactions.first { $0.id == id } }
            }
            Button("Sil", role: .destructive) {
                pendingDeletion = transactions.filter { ids.contains($0.id) }
            }
            .disabled(ids.isEmpty)
        } primaryAction: { ids in
            if let id = ids.first { editing = transactions.first { $0.id == id } }
        }
        .onDeleteCommand {
            pendingDeletion = transactions.filter { selection.contains($0.id) }
        }
        .onChange(of: selection) { _, newValue in
            router.selectedTransactionID = newValue.count == 1 ? newValue.first : nil
        }
        .sheet(item: $editing) { transaction in
            TransactionEditor(mode: .edit(transaction))
                .frame(minWidth: 460, minHeight: 480)
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? Text("Bu işlem silinsin mi?") : Text("\(pendingDeletion.count) işlem silinsin mi?"),
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                let store = LedgerStore(context: context)
                for transaction in pendingDeletion { try? store.delete(transaction) }
                selection.removeAll()
                pendingDeletion = []
            }
        }
    }
}

/// Denetçi paneli: seçili işlemin ayrıntısı.
struct TransactionInspector: View {
    @Query private var matches: [LedgerTransaction]
    @State private var editing: LedgerTransaction?

    init(id: UUID) {
        _matches = Query(filter: #Predicate<LedgerTransaction> { $0.id == id })
    }

    var body: some View {
        if let transaction = matches.first {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TransactionTitle(transaction: transaction).font(.headline)
                        HeroAmount(money: transaction.kind == .expense ? -transaction.amount : transaction.amount)
                    }
                }
                Section {
                    LabeledContent("Tarih") {
                        Text(transaction.date, format: .dateTime.day().month(.wide).year().hour().minute())
                    }
                    LabeledContent("Tür") { Text(transaction.kind.label) }
                    if let category = transaction.category {
                        LabeledContent("Kategori") { Text(verbatim: category.path) }
                    }
                    LabeledContent("Hesap") {
                        Text(verbatim: transaction.kind == .transfer
                             ? transaction.subtitle
                             : (transaction.account?.name ?? "—"))
                    }
                    if !transaction.note.isEmpty {
                        LabeledContent("Not") { Text(verbatim: transaction.note) }
                    }
                }
                Section {
                    Button("Düzenle…") { editing = transaction }
                }
            }
            .formStyle(.grouped)
            .sheet(item: $editing) { transaction in
                TransactionEditor(mode: .edit(transaction))
                    .frame(minWidth: 460, minHeight: 480)
            }
        } else {
            ContentUnavailableView("Seçim yok", systemImage: "sidebar.right",
                                   description: Text("Ayrıntısını görmek için bir kayıt seç."))
        }
    }
}
#endif
