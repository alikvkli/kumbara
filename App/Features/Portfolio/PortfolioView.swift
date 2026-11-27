import SwiftUI

/// Birikim/portföy (REQ-P3…P8). İçerik M2'de gelir.
struct PortfolioView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Birikim yok", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Altın, döviz veya kripto alımını kaydet; ortalama maliyetini ve bozdurma değerini burada gör.")
        }
        .navigationTitle("Birikim")
    }
}
