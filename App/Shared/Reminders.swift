import Foundation
import KumbaraCore
import KumbaraData
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

    static func cancel(_ rule: RecurringRule) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: rule)])
    }
}
