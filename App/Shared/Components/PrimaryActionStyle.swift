import SwiftUI

extension View {
    /// Ekrandaki tek birincil eylem (Kaydet, Onayla): cam + vurgu, ekranda en fazla bir tane
    /// (specs/06 §6.4, §9). Yazı rengini sistem zemine göre seçer (koyu modda açık vurgu üstünde
    /// siyah, 8.5:1); elle tint verilmez (specs/06 §3).
    func primaryActionStyle() -> some View {
        buttonStyle(.glassProminent)
    }
}
