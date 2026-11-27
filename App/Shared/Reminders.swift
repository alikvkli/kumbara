import Foundation
import KumbaraCore
import KumbaraData
import SwiftData
import UserNotifications

/// Yerel hatırlatmalar (specs/08 §2.2): tekrarlayan işlemin vade günü sabahı "onay bekliyor".
/// Kimlik kural başınadır; yeniden planlamak eskisinin yerine geçer.
@MainActor
enum Reminders {
    private static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }

    /// İzin, ilgili özellik ilk kullanılınca istenir (açılışta değil).
    static func requestAuthorizationIfNeeded() {
        guard !isUITesting else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func identifier(for rule: RecurringRule) -> String { "recurring:\(rule.id.uuidString)" }

    /// Her etkin kuralın bir sonraki vadesi için sabah 09:00 hatırlatması.
    static func schedule(_ rules: [RecurringRule], now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        guard !isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        for rule in rules {
            guard !rule.isPaused, let next = rule.schedule?.nextDue(after: now, calendar: calendar),
                  let currency = rule.account?.currency else {
                center.removePendingNotificationRequests(withIdentifiers: [identifier(for: rule)])
                continue
            }
            let content = UNMutableNotificationContent()
            let title = rule.merchant ?? rule.category?.name ?? String(localized: "Tekrarlayan işlem")
            content.title = title
            content.body = String(localized: "\(Money(rule.amount, currency).formatted(locale: locale)) · onay bekliyor")
            content.threadIdentifier = "recurring"
            var components = calendar.dateComponents([.year, .month, .day], from: next)
            components.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier(for: rule), content: content, trigger: trigger),
                       withCompletionHandler: nil)
        }
    }

    /// Kart son ödeme gününden 3 gün önce, 10:00 (specs/08 §3.1). Borç yoksa hatırlatma kaldırılır.
    static func scheduleCardDue(_ accounts: [LedgerAccount], context: ModelContext, now: Date = .now,
                                calendar: Calendar = .current, locale: Locale = .current) {
        guard !isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        let store = InstallmentStore(context: context)
        for account in accounts where account.kind == .card {
            let id = "card-due:\(account.id.uuidString)"
            guard !account.isArchived, let statement = try? store.statement(for: account, now: now, calendar: calendar),
                  statement.remainingDue.amount > 0,
                  let remind = calendar.date(byAdding: .day, value: -3, to: statement.last.due), remind > now else {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(account.name) son ödeme \(statement.last.due.formatted(.dateTime.day().month(.wide)))")
            content.body = String(localized: "Ekstre borcu \(statement.remainingDue.formatted(locale: locale))")
            content.threadIdentifier = "card"
            var components = calendar.dateComponents([.year, .month, .day], from: remind)
            components.hour = 10
            center.add(UNNotificationRequest(identifier: id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)),
                       withCompletionHandler: nil)
        }
    }

    /// Çalan fiyat alarmı: hemen gösterilir.
    static func priceAlertFired(_ alert: PriceAlert, quote: Quote, locale: Locale = .current) {
        guard !isUITesting, let rule = alert.rule else { return }
        let content = UNMutableNotificationContent()
        let price = rule.asset.formatPrice(quote.price(rule.priceKind), locale: locale)
        let threshold = rule.asset.formatPrice(rule.threshold, locale: locale)
        content.title = String(localized: "\(rule.asset.displayName()) \(price) ₺")
        content.body = rule.direction == .above
            ? String(localized: "\(threshold) ₺ üstüne çıktı · alarm kapandı, istersen yeniden kur.")
            : String(localized: "\(threshold) ₺ altına düştü · alarm kapandı, istersen yeniden kur.")
        content.sound = .default
        content.threadIdentifier = "price-alert"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "price-alert:\(alert.id.uuidString)",
                                                                     content: content, trigger: nil),
                                               withCompletionHandler: nil)
    }

    static func cancel(_ rule: RecurringRule) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: rule)])
    }
}
