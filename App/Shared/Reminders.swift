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

    static let monthlyReportID = "monthly-report"

    /// Ayın 1'i 09:00: "Kasım raporu hazır" (specs/10 §1, K1). Kapalıysa bekleyen bildirim kaldırılır.
    static func scheduleMonthlyReport(enabled: Bool, now: Date = .now, calendar: Calendar = .current) {
        guard !isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [monthlyReportID])
        guard enabled else { return }
        let nextMonth = LedgerMonth(containing: now, calendar: calendar).next
        let closing = LedgerMonth(containing: now, calendar: calendar).interval(in: calendar).start
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(closing.formatted(.dateTime.month(.wide))) raporu hazır")
        content.body = String(localized: "Ay nasıl geçti: harcaman, bütçen ve birikimin tek sayfada.")
        content.threadIdentifier = "report"
        content.userInfo = ["link": DeepLink.report.url.absoluteString]
        let components = DateComponents(year: nextMonth.year, month: nextMonth.month, day: 1, hour: 9)
        center.add(UNNotificationRequest(identifier: monthlyReportID, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)),
                   withCompletionHandler: nil)
    }

    /// Aboneliğin fiyatı arttı: hemen, bir kez (specs/10 §2).
    static func subscriptionIncreased(_ subscription: SubscriptionDetector.Subscription, locale: Locale = .current) {
        guard !isUITesting, let previous = subscription.previousAmount, let increase = subscription.priceIncrease else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(subscription.name) fiyatı arttı")
        let old = Money(previous, .TRY).formatted(locale: locale)
        let new = Money(subscription.lastAmount, .TRY).formatted(locale: locale)
        content.body = String(localized: "\(old) → \(new) (\(increase.formattedPercent(locale: locale, fractionDigits: 0, sign: .always)))")
        content.threadIdentifier = "subscription"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "subscription:\(subscription.merchantKey)",
                                                                     content: content, trigger: nil),
                                               withCompletionHandler: nil)
    }

    /// Takvimli birikim planlarının sıradaki vadesi, 09:00 (specs/10 §7). Duraklatılan ya da silinen planın
    /// bekleyen hatırlatması kaldırılır.
    static func schedulePlans(_ plans: [SavingsPlan], now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        guard !isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix("plan:") }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for plan in plans where plan.isActive {
            guard let rule = plan.rule, let next = rule.schedule?.nextDue(after: now, calendar: calendar) else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Birikim planı: \(PlanText.title(rule, locale: locale))")
            content.body = String(localized: "Bugün alım günü. Dokun, alım o anki satış fiyatıyla hazırlansın.")
            content.threadIdentifier = "plan"
            content.userInfo = ["link": DeepLink.plan.url.absoluteString, "planID": plan.id.uuidString]
            var components = calendar.dateComponents([.year, .month, .day], from: next)
            components.hour = 9
            center.add(UNNotificationRequest(identifier: "plan:\(plan.id.uuidString)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)),
                       withCompletionHandler: nil)
        }
    }

    /// Alacak/borç hatırlatması: seçilen gün 10:00 (specs/10 §4). Bakiye kapanınca kaldırılır.
    static func schedulePerson(_ person: Person, balance: Decimal, locale: Locale = .current, calendar: Calendar = .current) {
        guard !isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        let id = "person:\(person.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let day = person.remindAt, balance != 0, day > .now || calendar.isDateInToday(day) else { return }
        let content = UNMutableNotificationContent()
        let amount = Money(abs(balance), .TRY).formatted(locale: locale)
        content.title = person.name
        content.body = balance > 0
            ? String(localized: "Alacağın \(amount) · hatırlatma günü")
            : String(localized: "Borcun \(amount) · ödeme günü")
        content.threadIdentifier = "person"
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 10
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)),
                   withCompletionHandler: nil)
    }

    static func cancel(_ rule: RecurringRule) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: rule)])
    }
}
