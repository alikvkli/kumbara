import SwiftUI

/// Bütçeler (REQ-B1, B2). İçerik M4'te gelir.
struct BudgetView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Bütçe yok", systemImage: "chart.pie")
        } description: {
            Text("Kategori bazında aylık limit belirle; %80 ve %100'de haber verelim.")
        }
        .navigationTitle("Bütçe")
    }
}
