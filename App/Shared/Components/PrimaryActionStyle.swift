import SwiftUI

extension View {
    /// Ekrandaki tek birincil eylem (Kaydet, Onayla): cam + vurgu, ekranda en fazla bir tane
    /// (specs/06 §6.4, §9). Zemin `AccentProminent`: koyu modda beyaz yazıyla ≥ 4.5:1 kontrast
    /// için `AccentColor`'dan koyu (specs/06 §3).
    func primaryActionStyle() -> some View {
        buttonStyle(.glassProminent)
            .tint(Color("AccentProminent"))
    }
}
