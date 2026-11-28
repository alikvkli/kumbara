import Foundation
import KumbaraCore
import KumbaraData
import UserNotifications

/// Kira yenilemesi hatırlatmaları (specs/12): yenilemeden 30 gün önce 10:00 ve TÜİK'in oranı açıkladığı
/// gün 11:00. Kimlikler sözleşme başınadır; yeniden planlamak eskisinin yerine geçer.
@MainActor
enum RentReminders {
    private static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }

    static func identifiers(_ id: UUID) -> [String] { ["rent:\(id.uuidString)", "rent-rate:\(id.uuidString)"] }

    static func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(id))
    }

    static func schedule(_ contracts: [RentContract], now: Date = .now, calendar: Calendar = .current) {
        guard !isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        for contract in contracts {
            center.removePendingNotificationRequests(withIdentifiers: identifiers(contract.id))
            let ids = identifiers(contract.id)
            let next = nextRenewal(of: contract, now: now, calendar: calendar)
            let reference = RentIncrease.referenceMonth(forRenewal: LedgerMonth(containing: next.date, calendar: calendar))
            let referenceTitle = reference.interval(in: calendar).start.formatted(.dateTime.month(.wide).year())
            let name = contract.name.isEmpty ? String(localized: "Kira") : contract.name

            if let remind = calendar.date(byAdding: .day, value: -30, to: next.date),
               let fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: remind), fire > now {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Kira yenilemesi yaklaşıyor")
                content.body = String(localized: "\(name): \(next.date.formatted(.dateTime.day().month(.wide))) günü \(next.year). kira yılı başlıyor. Yasal artış sınırı \(referenceTitle) TÜFE verisiyle belli olur.")
                content.threadIdentifier = "rent"
                add(ids[0], content, at: fire, calendar: calendar)
            }

            let published = RentIncrease.publicationDate(of: reference, calendar: calendar)
            if let fire = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: published), fire > now,
               RentIncrease.averageChange(for: reference, cpi: CPIData.turkey) == nil {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Kira artış oranı açıklandı")
                content.body = String(localized: "TÜİK bugün \(referenceTitle) TÜFE verisini açıkladı. \(name) için 12 aylık ortalamayı girip yeni kira sınırını gör.")
                content.threadIdentifier = "rent"
                add(ids[1], content, at: fire, calendar: calendar)
            }
        }
    }

    /// Bugünden sonraki ilk yıl dönümü ve başlayacak kira yılı.
    private static func nextRenewal(of contract: RentContract, now: Date, calendar: Calendar) -> (date: Date, year: Int) {
        let relevant = RentIncrease.relevantRenewal(start: contract.start, now: now, calendar: calendar)
        guard relevant.date <= calendar.startOfDay(for: now) else { return relevant }
        return (RentIncrease.anniversary(relevant.year, of: contract.start, calendar: calendar), relevant.year + 1)
    }

    private static func add(_ id: String, _ content: UNMutableNotificationContent, at date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content,
                                  trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)),
            withCompletionHandler: nil)
    }
}
