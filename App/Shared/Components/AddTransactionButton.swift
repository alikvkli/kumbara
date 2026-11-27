import SwiftUI

/// Boş durumlardaki tek eylem (specs/06 §9: boş durum = ContentUnavailableView + tek eylem).
struct AddTransactionButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button("İşlem ekle") { router.isPresentingQuickAdd = true }
    }
}
