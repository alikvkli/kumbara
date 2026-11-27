import Foundation
import Testing
@testable import KumbaraCore

@Suite("Canlı tarama rehberi")
struct LiveScanGuideTests {
    private func receipt(total: String) -> [TextLine] {
        let rows = ["MİGROS TİC. A.Ş.", "TARİH: 27.11.2026  SAAT: 14:35", "SÜT 1L  *42,50", "TOPKDV  *170,12", "TOPLAM  *\(total)", "KREDİ KARTI  *\(total)"]
        return rows.enumerated().map { index, text in
            TextLine(text: text, box: TextBox(x: 0.1, y: 0.1 + Double(index) * 0.08, width: 0.8, height: 0.05), confidence: 0.95)
        }
    }

    @Test("Aynı toplam üç karede okununca bulundu; öncesinde sabitleniyor")
    func stabilises() {
        var guide = LiveScanGuide()
        #expect(guide.observe(receipt(total: "1.249,90")) == .steadying(Decimal(string: "1249.9")!))
        #expect(guide.observe(receipt(total: "1.249,90")) == .steadying(Decimal(string: "1249.9")!))
        #expect(guide.observe(receipt(total: "1.249,90")) == .found(Decimal(string: "1249.9")!))
    }

    @Test("Okuma değişirse seri baştan başlar")
    func changingReadingRestarts() {
        var guide = LiveScanGuide()
        guide.observe(receipt(total: "1.249,90"))
        guide.observe(receipt(total: "1.249,90"))
        #expect(guide.observe(receipt(total: "1.248,90")) == .steadying(Decimal(string: "1248.9")!))
    }

    @Test("Boş kare ve toplamı olmayan yazı")
    func emptyAndSearching() {
        var guide = LiveScanGuide()
        #expect(guide.observe([]) == .empty)
        #expect(guide.observe([TextLine(text: "Merhaba dünya", box: TextBox(x: 0, y: 0, width: 1, height: 0.1))]) == .searching)
    }

    @Test("Bulunduktan sonra tek kaçan kare durumu silmez")
    func keepsFoundOnDroppedFrame() {
        var guide = LiveScanGuide(requiredFrames: 2)
        guide.observe(receipt(total: "250,00"))
        guide.observe(receipt(total: "250,00"))
        #expect(guide.observe([TextLine(text: "bulanık", box: TextBox(x: 0, y: 0, width: 1, height: 0.1))]) == .found(250))
    }
}
