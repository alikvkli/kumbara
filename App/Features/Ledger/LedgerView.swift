import SwiftUI

/// İşlem listesi (iOS `List`, macOS `Table`). İçerik M1'de (T1.4) gelir.
struct LedgerView: View {
    var body: some View {
        ContentUnavailableView {
            Label("İşlem yok", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Eklediğin ve fişten aktardığın işlemler burada listelenir.")
        } actions: {
            AddTransactionButton()
        }
        .navigationTitle("İşlemler")
    }
}
