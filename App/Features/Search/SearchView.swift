import KumbaraData
import SwiftData
import SwiftUI

/// iOS arama sekmesi (specs/06 §6.1, T1.4).
struct SearchView: View {
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @State private var filter = TransactionFilter()

    private var results: [LedgerTransaction] {
        filter.query.isEmpty ? [] : transactions.filter(filter.matches)
    }

    var body: some View {
        TransactionList(transactions: results)
            .overlay {
                if filter.query.isEmpty {
                    ContentUnavailableView("İşlemlerinde ara", systemImage: "magnifyingglass",
                                           description: Text("Satıcı, not veya kategori adı yaz."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: filter.query)
                }
            }
            .navigationTitle("Ara")
            .searchable(text: $filter.query, prompt: Text("Satıcı, not, kategori"))
    }
}
