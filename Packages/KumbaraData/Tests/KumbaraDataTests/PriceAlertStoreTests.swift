import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("PriceAlertStore (specs/08 §5)")
struct PriceAlertStoreTests {
    let container: ModelContainer
    let store: PriceAlertStore

    init() throws {
        container = try KumbaraContainer.make(inMemory: true)
        store = PriceAlertStore(context: container.mainContext)
    }

    func gram(_ bid: Decimal, derived: Bool = false) -> [AssetCode: Quote] {
        [.gold(.gram24): Quote(asset: .gold(.gram24), bid: bid, ask: bid + 1, asOf: .now, source: .truncgil, isDerived: derived)!]
    }

    @Test("AC-M4-1 kalıcı katmanda: bir kez çalar ve kapanır; yeniden kurulabilir")
    func lifecycle() throws {
        let rule = PriceAlertRule(asset: .gold(.gram24), direction: .above, threshold: 6100)
        let alert = try store.create(rule, current: gram(6000)[.gold(.gram24)])
        #expect(try store.activeAssets() == [.gold(.gram24)])
        #expect(try store.evaluate(gram(6200, derived: true)).isEmpty)
        #expect(try store.evaluate(gram(6120)).count == 1)
        #expect(!alert.isActive && alert.firedPrice == "6120")
        #expect(try store.evaluate(gram(6130)).isEmpty)
        #expect(try store.activeAssets().isEmpty)

        try store.rearm(alert, current: gram(6130)[.gold(.gram24)])
        #expect(try store.evaluate(gram(6140)).isEmpty)   // zaten üstünde: çalmaz
        #expect(try store.evaluate(gram(6050)).isEmpty)
        #expect(try store.evaluate(gram(6101)).count == 1)
    }
}
