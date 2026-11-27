import Foundation
import KumbaraCore
import KumbaraData
import SwiftData

/// Abonelik zammı bildirimi (specs/10 §2): zamlı ödeme kaydedilince bir kez. Eski bir zam (içe aktarılan
/// geçmiş) bildirilmez; yalnız son 14 günde yapılan ödeme.
@MainActor
enum InsightMonitor {
    private static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }

    static func check(_ context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        guard !isUITesting else { return }
        let store = InsightStore(context: context)
        let log = BudgetStore(context: context)
        guard let subscriptions = try? store.subscriptions(now: now, calendar: calendar) else { return }
        for subscription in subscriptions where subscription.previousAmount != nil {
            guard let last = subscription.payments.last?.date,
                  now.timeIntervalSince(last) < 14 * 86_400 else { continue }
            let key = InsightStore.increaseKey(subscription, calendar: calendar)
            guard (try? log.wasNotified(key)) == false else { continue }
            try? log.markNotified(key)
            Reminders.subscriptionIncreased(subscription)
        }
    }
}
