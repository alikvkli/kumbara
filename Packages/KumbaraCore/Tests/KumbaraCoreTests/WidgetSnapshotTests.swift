import Foundation
import Testing
@testable import KumbaraCore

@Suite("Widget anlık görüntüsü (specs/09 §4)")
struct WidgetSnapshotTests {
    @Test("Yaz → oku aynı; Decimal hassasiyeti korunur")
    func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var snapshot = WidgetSnapshot.placeholder
        snapshot.createdAt = Date(timeIntervalSince1970: 1_793_000_000)
        snapshot.prices[0].asOf = snapshot.createdAt
        snapshot.prices[1].asOf = snapshot.createdAt
        snapshot.portfolioTotal = Decimal(string: "285400.37")
        snapshot.upcoming = snapshot.upcoming?.enumerated().map { index, item in
            var item = item
            item.date = snapshot.createdAt.addingTimeInterval(Double(index + 1) * 86_400)
            return item
        }
        let url = WidgetSnapshotStore.url(in: directory)
        try WidgetSnapshotStore.write(snapshot, to: url)
        #expect(WidgetSnapshotStore.read(from: url) == snapshot)
    }

    @Test("Eski özet (yaklaşan ödemeler alanı yok) okunur")
    func oldSnapshotDecodes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var snapshot = WidgetSnapshot.placeholder
        snapshot.upcoming = nil
        let url = WidgetSnapshotStore.url(in: directory)
        try WidgetSnapshotStore.write(snapshot, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("upcoming"))
        #expect(WidgetSnapshotStore.read(from: url)?.upcoming == nil)
    }

    @Test("Widget fiyatı tazeler; gün değişince günlük değişim yeniden hesaplanır")
    func updatingPrice() {
        let calendar = Calendar(identifier: .gregorian)
        let monday = Date(timeIntervalSince1970: 1_793_000_000)
        var snapshot = WidgetSnapshot.placeholder
        snapshot.prices[0] = .init(assetID: "gold.gram24", name: "Gram altın", price: 6_000, dayChange: nil, asOf: monday)
        let sameDay = snapshot.updating(price: "gold.gram24", to: 6_060, asOf: monday.addingTimeInterval(600), calendar: calendar)
        #expect(sameDay.prices[0].price == 6_060)
        #expect(sameDay.prices[0].dayChange == nil)
        let nextDay = snapshot.updating(price: "gold.gram24", to: 6_060, asOf: monday.addingTimeInterval(86_400), calendar: calendar)
        #expect(nextDay.prices[0].dayChange == Decimal(string: "0.01"))
        // Eski fiyat yenisinin üzerine yazmaz.
        #expect(snapshot.updating(price: "gold.gram24", to: 1, asOf: monday.addingTimeInterval(-60), calendar: calendar) == snapshot)
    }
}
