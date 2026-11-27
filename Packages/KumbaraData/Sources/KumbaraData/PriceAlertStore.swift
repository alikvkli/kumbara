import Foundation
import KumbaraCore
import SwiftData

/// Fiyat alarmları (REQ-M4, specs/08 §5): kurma, her fiyat yenilemesinde değerlendirme.
@MainActor
public struct PriceAlertStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func alerts() throws -> [PriceAlert] {
        try context.fetch(FetchDescriptor<PriceAlert>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    public func activeAssets() throws -> Set<AssetCode> {
        Set(try alerts().filter(\.isActive).compactMap { $0.rule?.asset })
    }

    /// `current`: kurulduğu andaki fiyat; koşul zaten sağlanıyorsa alarm hemen çalmaz.
    @discardableResult
    public func create(_ rule: PriceAlertRule, current: Quote?) throws -> PriceAlert {
        let alert = PriceAlert(rule: rule)
        alert.lastSatisfied = current.flatMap(rule.isSatisfied(by:))
        context.insert(alert)
        try context.save()
        return alert
    }

    /// Yeniden kur: çalmış alarmı aynı koşulla etkinleştirir (bugünkü fiyata göre).
    public func rearm(_ alert: PriceAlert, current: Quote?) throws {
        alert.isActive = true
        alert.firedAt = nil
        alert.firedPrice = nil
        alert.lastSatisfied = current.flatMap { alert.rule?.isSatisfied(by: $0) }
        try context.save()
    }

    public func delete(_ alert: PriceAlert) throws {
        context.delete(alert)
        try context.save()
    }

    /// Yeni fiyatlarla değerlendirir; çalan alarmlar kapanır ve döner (bildirim için).
    @discardableResult
    public func evaluate(_ quotes: [AssetCode: Quote], now: Date = .now) throws -> [(alert: PriceAlert, quote: Quote)] {
        var fired: [(PriceAlert, Quote)] = []
        var changed = false
        for alert in try alerts() where alert.isActive {
            guard let rule = alert.rule, let quote = quotes[rule.asset] else { continue }
            let evaluation = rule.evaluate(quote, previous: alert.lastSatisfied)
            if evaluation.satisfied != alert.lastSatisfied {
                alert.lastSatisfied = evaluation.satisfied
                changed = true
            }
            if evaluation.fires {
                alert.isActive = false
                alert.firedAt = now
                alert.firedPrice = quote.price(rule.priceKind).canonicalString
                fired.append((alert, quote))
                changed = true
            }
        }
        if changed { try context.save() }
        return fired
    }
}
