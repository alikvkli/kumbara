import Foundation
import Testing
@testable import KumbaraCore

@Suite("Fiyat alarmı (specs/08 §5)")
struct PriceAlertTests {
    func quote(_ bid: Decimal, derived: Bool = false, source: ProviderID = .truncgil) -> Quote {
        Quote(asset: .gold(.gram24), bid: bid, ask: bid + 1, asOf: .now, source: source, isDerived: derived)!
    }
    let rule = PriceAlertRule(asset: .gold(.gram24), direction: .above, threshold: 6100)

    @Test("AC-M4-1: 6.120'de bir kez çalar, 6.130'da çalmaz; tahmini fiyat çaldırmaz")
    func crossing() {
        var state = rule.evaluate(quote(6000), previous: nil)   // kurulduğu an: altında
        #expect(!state.fires && state.satisfied == false)
        state = rule.evaluate(quote(6200, derived: true), previous: state.satisfied)
        #expect(!state.fires && state.satisfied == false)       // tahmini yok sayılır
        state = rule.evaluate(quote(6120), previous: state.satisfied)
        #expect(state.fires)
        state = rule.evaluate(quote(6130), previous: state.satisfied)
        #expect(!state.fires)
    }

    @Test("Kurulduğunda koşul zaten sağlanıyorsa çalmaz; geri dönüp yeniden geçerse çalar")
    func alreadySatisfied() {
        var state = rule.evaluate(quote(6150), previous: nil)
        #expect(!state.fires && state.satisfied == true)
        state = rule.evaluate(quote(6050), previous: state.satisfied)
        #expect(!state.fires)
        state = rule.evaluate(quote(6100), previous: state.satisfied)
        #expect(state.fires)                                     // eşit = geçti
    }

    @Test("Altına düşerse; fiyat tipi; başka varlık ve elle fiyat yok sayılır")
    func belowAndKinds() {
        let below = PriceAlertRule(asset: .gold(.gram24), direction: .below, threshold: 5500, priceKind: .ask)
        #expect(below.evaluate(quote(5499), previous: false).fires)            // satış 5500 ≤ 5500: geçti
        #expect(below.isSatisfied(by: quote(5499)) == true)                     // ask 5500 ≤ 5500
        #expect(below.isSatisfied(by: quote(5500)) == false)                    // ask 5501
        #expect(below.isSatisfied(by: quote(5000, source: .manual)) == nil)
        let usd = Quote(asset: .fx(.USD), bid: 40, ask: 41, asOf: .now, source: .tcmb)!
        #expect(below.isSatisfied(by: usd) == nil)
    }
}
