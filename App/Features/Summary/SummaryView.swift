import SwiftUI

/// Aylık özet (REQ-B3, B4). İçerik M1'de (T1.6) gelir.
struct SummaryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Henüz işlem yok", systemImage: "square.text.square")
        } description: {
            Text("İlk gelir ya da giderini ekle; aylık özet burada görünecek.")
        } actions: {
            AddTransactionButton()
        }
        .navigationTitle("Özet")
    }
}
