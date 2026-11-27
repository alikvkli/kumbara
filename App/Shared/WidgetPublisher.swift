import Foundation
import KumbaraCore
import KumbaraData
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Widget'lar ve menü çubuğu için özeti App Group'a yazar (specs/09 §4). Her kayıttan ve başarılı
/// fiyat yenilemesinden sonra çağrılır; içerik değişmediyse widget'lar yeniden çizdirilmez.
@MainActor
enum WidgetPublisher {
    static let hideAmountsKey = "widget.hideAmounts"
    static let priceAssets: [AssetCode] = [.gold(.gram24), .gold(.quarter), .fx(.USD), .fx(.EUR)]
    private static var lastPublished: WidgetSnapshot?

    static func publish(context: ModelContext, board: PriceBoard, now: Date = .now, calendar: Calendar = .current) {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing"), let url = WidgetSnapshotStore.shared() else { return }
        let snapshot = makeSnapshot(context: context, board: board, now: now, calendar: calendar)
        var comparable = snapshot
        comparable.createdAt = lastPublished?.createdAt ?? snapshot.createdAt
        guard comparable != lastPublished else { return }
        do {
            try WidgetSnapshotStore.write(snapshot, to: url)
            lastPublished = snapshot
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            // Widget eski özeti göstermeye devam eder; uygulama işlevi etkilenmez.
        }
    }

    static func makeSnapshot(context: ModelContext, board: PriceBoard, now: Date, calendar: Calendar) -> WidgetSnapshot {
        let priceKind = PriceKind(rawValue: UserDefaults.standard.string(forKey: SettingsKey.priceKind) ?? "") ?? .bid
        let portfolio = PortfolioStore(context: context, calendar: calendar)
        let history = (try? portfolio.priceHistory(priceKind: priceKind)) ?? [:]
        let today = calendar.startOfDay(for: now)

        let prices: [WidgetSnapshot.Price] = priceAssets.compactMap { asset in
            guard let quote = board.quote(asset) else { return nil }
            let price = quote.price(priceKind)
            let previous = history[asset]?.last { $0.date < today }?.price
            let change = previous.flatMap { $0 > 0 ? (price - $0) / $0 : nil }
            return .init(assetID: asset.id, name: asset.shortName, price: price, dayChange: change, asOf: quote.asOf)
        }

        // Birikim: fiyatı olan açık pozisyonlar.
        let positions = ((try? portfolio.positions()) ?? []).filter(\.isOpen)
        let customNames = Dictionary(((try? portfolio.customAssets()) ?? []).map { ($0.code, $0.name) }, uniquingKeysWith: { a, _ in a })
        var total = Decimal(0), cost = Decimal(0)
        var holdings: [WidgetSnapshot.Holding] = []
        for position in positions {
            guard let quote = board.quote(position.asset) else { continue }
            let valuation = Valuation(position: position, quote: quote, priceKind: priceKind)
            total += valuation.value
            cost += position.costBasis
            holdings.append(.init(name: position.asset.displayName(customName: customNames[position.asset]),
                                  value: valuation.value, pnlRatio: valuation.unrealizedReturn))
        }
        holdings.sort { $0.value > $1.value }

        // Bütçe: Özet'teki "bugün harcayabileceğin" ile aynı hesap (REQ-B4).
        let month = LedgerMonth(containing: now, calendar: calendar)
        var budget: WidgetSnapshot.Budget?
        let overall = (try? BudgetStore(context: context).statuses(for: month, calendar: calendar))?.first { $0.categoryID == nil }
        let net = (try? LedgerStore(context: context).summary(for: month, currency: .TRY, calendar: calendar))?.net
        if let remaining = overall?.remaining ?? net,
           let allowance = DailyAllowance(remaining: remaining, month: month, today: now, calendar: calendar) {
            let fraction = overall.flatMap { status -> Double? in
                guard status.limit.amount > 0 else { return nil }
                return (status.spent.amount / status.limit.amount as NSDecimalNumber).doubleValue
            }
            budget = .init(perDay: allowance.perDay.amount, remainingDays: allowance.remainingDays,
                           spentFraction: fraction, remaining: remaining.amount)
        }

        return WidgetSnapshot(createdAt: now, prices: prices,
                              portfolioTotal: positions.isEmpty ? nil : total,
                              portfolioPnL: positions.isEmpty ? nil : total - cost,
                              portfolioPnLRatio: cost > 0 ? (total - cost) / cost : nil,
                              holdings: Array(holdings.prefix(3)), budget: budget,
                              hidesAmounts: UserDefaults.standard.bool(forKey: hideAmountsKey))
    }
}
