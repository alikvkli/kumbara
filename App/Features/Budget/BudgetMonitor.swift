import Foundation
import KumbaraCore
import KumbaraData
import SwiftData
import UserNotifications

/// Bütçe eşik bildirimleri (REQ-B2, specs/08 §1.3).
///
/// Her kayıttan sonra (`ModelContext.didSave`) bu ayın bütçeleri değerlendirilir; ulaşılan her eşik
/// (%80, %100) için bütçe-ay-eşik başına **bir** yerel bildirim gönderilir. Tekrarı `NotificationLog`
/// engeller; kaydı hangi ekranın yaptığından bağımsızdır (hızlı ekleme, fiş onayı, düzenleme).
@MainActor
final class BudgetMonitor: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BudgetMonitor()

    private var isChecking = false
    /// UI testleri bildirim izni penceresi açmamalı.
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    func start() {
        guard !isUITesting else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// İzin, ilk bütçe oluşturulunca istenir (açılışta değil).
    func requestAuthorizationIfNeeded() { Reminders.requestAuthorizationIfNeeded() }

    func check(_ context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        guard !isUITesting, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let store = BudgetStore(context: context)
        let month = LedgerMonth(containing: now, calendar: calendar)
        guard let budgets = try? store.budgets(), !budgets.isEmpty,
              let statuses = try? store.statuses(for: month, today: now, calendar: calendar) else { return }
        let names = Dictionary(budgets.map { ($0.id, $0.isOverall ? nil : $0.category?.name) }, uniquingKeysWith: { a, _ in a })
        let days = DailyAllowance(remaining: .zero(.TRY), month: month, today: now, calendar: calendar)?.remainingDays

        for status in statuses {
            // Yalnız en yüksek ulaşılan eşik bildirilir; diğerleri sessizce işaretlenir (aynı anda iki bildirim olmasın).
            let reached = BudgetMath.reachedThresholds(status)
            let pending = reached.filter { (try? store.wasNotified(BudgetStore.notificationKey(budget: status.id, month: month, threshold: $0))) == false }
            guard let highest = pending.max() else { continue }
            for threshold in pending {
                try? store.markNotified(BudgetStore.notificationKey(budget: status.id, month: month, threshold: threshold))
            }
            send(status: status, threshold: highest, name: names[status.id] ?? nil, remainingDays: days, month: month)
        }
    }

    private func send(status: BudgetStatus, threshold: Int, name: String?, remainingDays: Int?, month: LedgerMonth) {
        let locale = Locale.current
        let content = UNMutableNotificationContent()
        let subject = name.map { String(localized: "\($0) bütçesi") } ?? String(localized: "Aylık bütçe")
        if threshold >= 100 {
            content.title = String(localized: "\(subject) aşıldı")
            content.body = String(localized: "\((status.spent - status.limit).formatted(locale: locale, fractionDigits: 0)) fazla harcandı.")
        } else {
            content.title = String(localized: "\(subject) %\(threshold) doldu")
            let remaining = status.remaining.formatted(locale: locale, fractionDigits: 0)
            content.body = remainingDays.map { String(localized: "Kalan \(remaining) · \($0) gün") } ?? String(localized: "Kalan \(remaining)")
        }
        content.sound = .default
        content.threadIdentifier = "budget"
        let id = BudgetStore.notificationKey(budget: status.id, month: month, threshold: threshold)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // Uygulama öndeyken de afiş göster: eşiği geçiren kaydı kullanıcı az önce yaptı.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
