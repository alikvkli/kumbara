import Foundation
import KumbaraCore
import SwiftData

/// "Alabilir miyim?" bağlamı (specs/10 §3).
extension InsightStore {
    /// Bu ayın kalanı (genel bütçe varsa onun kalanı, yoksa ayın neti) ve son 3 ayın birikim hızı.
    public func purchaseContext(now: Date = .now, calendar: Calendar = .current) throws -> PurchasePlanner.Context {
        let month = LedgerMonth(containing: now, calendar: calendar)
        let overall = try BudgetStore(context: context).statuses(for: month, today: now, calendar: calendar)
            .first { $0.categoryID == nil }
        let ledger = LedgerStore(context: context)
        let net = try ledger.summary(for: month, currency: .TRY, calendar: calendar).net.amount
        let all = try context.fetch(FetchDescriptor<LedgerTransaction>()).map(\.entry)
        return PurchasePlanner.Context(today: now, remaining: overall?.remaining.amount ?? net, hasBudget: overall != nil,
                                       monthlySaving: PurchasePlanner.monthlySaving(entries: all, before: month, calendar: calendar))
    }

    /// Hedeflerin TL cinsinden kalanı; miktar hedefleri alış (satış) fiyatıyla çevrilir. Fiyatı bilinmeyen
    /// ve ulaşılmış hedefler atlanır. Tarihi en yakın olan önce.
    public func goalsForPurchase(prices: [AssetCode: Decimal], now: Date = .now,
                                 calendar: Calendar = .current) throws -> [PurchasePlanner.Goal] {
        let store = GoalStore(context: context)
        return try store.goals()
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .compactMap { goal in
                guard let value = goal.goal,
                      let progress = try store.progress(of: goal, prices: prices, now: now, calendar: calendar),
                      !progress.isReached else { return nil }
                switch value.target {
                case .amount:
                    return PurchasePlanner.Goal(name: goal.name, remaining: progress.remaining)
                case let .quantity(asset, _):
                    guard let price = prices[asset] else { return nil }
                    return PurchasePlanner.Goal(name: goal.name, remaining: progress.remaining * price)
                }
            }
    }
}
