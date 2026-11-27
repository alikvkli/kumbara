import SwiftUI

/// iOS arama sekmesi (specs/06 §6.1). Sonuçlar M1'de (T1.4) gelir.
struct SearchView: View {
    @State private var query = ""

    var body: some View {
        ContentUnavailableView.search(text: query)
            .navigationTitle("Ara")
            .searchable(text: $query, prompt: Text("Satıcı, not, kategori"))
    }
}
