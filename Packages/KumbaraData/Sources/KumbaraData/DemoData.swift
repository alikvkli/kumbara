import Foundation
import KumbaraCore
import SwiftData

/// Ekran görüntüleri ve önizlemeler için örnek veri. Yalnız bellek içi depoda kullanılır
/// (`-demo-data` başlatma argümanı); kullanıcının gerçek deposuna asla yazılmaz.
@MainActor
public enum DemoData {
    private struct Item {
        let monthOffset: Int
        let day: Int
        let kind: TransactionKind
        let amount: String
        let account: String
        let category: String?
        let merchant: String?
        var toAccount: String? = nil
        var note: String = ""
    }

    private static let items: [Item] = [
        // Geçen ay (karşılaştırma için)
        Item(monthOffset: -1, day: 1, kind: .income, amount: "62000", account: "bank", category: "salary", merchant: nil),
        Item(monthOffset: -1, day: 1, kind: .expense, amount: "22500", account: "bank", category: "housing.rent", merchant: nil),
        Item(monthOffset: -1, day: 6, kind: .expense, amount: "3420.60", account: "card", category: "market.food", merchant: "Migros"),
        Item(monthOffset: -1, day: 9, kind: .expense, amount: "2600", account: "card", category: "transport.fuel", merchant: "Opet"),
        Item(monthOffset: -1, day: 15, kind: .expense, amount: "1940", account: "card", category: "dining.restaurant", merchant: "Köfteci Yusuf"),
        Item(monthOffset: -1, day: 21, kind: .expense, amount: "2875.40", account: "card", category: "market.food", merchant: "CarrefourSA"),
        // Bu ay
        Item(monthOffset: 0, day: 1, kind: .income, amount: "62000", account: "bank", category: "salary", merchant: nil),
        Item(monthOffset: 0, day: 1, kind: .expense, amount: "22500", account: "bank", category: "housing.rent", merchant: nil, note: "Kasım kirası"),
        Item(monthOffset: 0, day: 2, kind: .expense, amount: "1249.90", account: "card", category: "market.food", merchant: "Migros"),
        Item(monthOffset: 0, day: 3, kind: .expense, amount: "2000", account: "card", category: "transport.fuel", merchant: "Opet"),
        Item(monthOffset: 0, day: 4, kind: .expense, amount: "185", account: "card", category: "dining.cafe", merchant: "Starbucks"),
        Item(monthOffset: 0, day: 5, kind: .expense, amount: "229.99", account: "card", category: "subscriptions", merchant: "Netflix"),
        Item(monthOffset: 0, day: 6, kind: .expense, amount: "1180.40", account: "bank", category: "housing.electricity", merchant: "Enerjisa"),
        Item(monthOffset: 0, day: 8, kind: .expense, amount: "642.50", account: "cash", category: "market.food", merchant: "A101"),
        Item(monthOffset: 0, day: 10, kind: .expense, amount: "486", account: "card", category: "dining.delivery", merchant: "Yemeksepeti"),
        Item(monthOffset: 0, day: 12, kind: .expense, amount: "500", account: "cash", category: "transport.public", merchant: "İstanbulkart"),
        Item(monthOffset: 0, day: 14, kind: .expense, amount: "312.75", account: "card", category: "health.pharmacy", merchant: "Işık Eczanesi"),
        Item(monthOffset: 0, day: 15, kind: .transfer, amount: "3000", account: "bank", category: nil, merchant: nil, toAccount: "cash"),
        Item(monthOffset: 0, day: 18, kind: .expense, amount: "2130.15", account: "card", category: "market.food", merchant: "Migros"),
        Item(monthOffset: 0, day: 20, kind: .expense, amount: "1899", account: "card", category: "clothing", merchant: "Zara"),
        Item(monthOffset: 0, day: 22, kind: .income, amount: "7500", account: "bank", category: "freelance", merchant: nil, note: "Logo tasarımı"),
        Item(monthOffset: 0, day: 24, kind: .expense, amount: "1750", account: "card", category: "transport.fuel", merchant: "Opet"),
        Item(monthOffset: 0, day: 26, kind: .expense, amount: "740", account: "card", category: "dining.restaurant", merchant: "Köfteci Yusuf"),
    ]

    /// Varsayılan seed'den sonra çağrılır. `now`'dan sonraki günler eklenmez.
    public static func load(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        let cash = try context.fetch(FetchDescriptor<LedgerAccount>()).first { $0.kind == .cash }
        cash?.openingBalance = Money(1_500, .TRY)
        let bank = LedgerAccount(name: "Maaş hesabı", kind: .bank, currency: .TRY, openingBalance: 18_500, sortIndex: 1)
        let card = LedgerAccount(name: "Kredi kartı", kind: .card, currency: .TRY, sortIndex: 2)
        context.insert(bank)
        context.insert(card)
        try context.save()

        let accounts = ["cash": cash, "bank": bank, "card": card]
        let categories = Dictionary(
            try context.fetch(FetchDescriptor<LedgerCategory>()).compactMap { c in c.seedKey.map { ($0, c) } },
            uniquingKeysWith: { first, _ in first })
        let store = LedgerStore(context: context)
        let thisMonth = LedgerMonth(containing: now, calendar: calendar)

        for (index, item) in items.enumerated() {
            let month = item.monthOffset == 0 ? thisMonth : thisMonth.previous
            guard let date = calendar.date(from: DateComponents(
                year: month.year, month: month.month, day: item.day, hour: 9 + index % 10, minute: (index * 7) % 60)),
                  date <= now,
                  let account = accounts[item.account] ?? nil
            else { continue }
            let draft = TransactionDraft(
                kind: item.kind,
                amount: Decimal(canonical: item.amount),
                date: date,
                account: account.ref,
                toAccount: item.toAccount.flatMap { accounts[$0] ?? nil }?.ref,
                category: item.category.flatMap { categories[$0] }?.ref,
                merchant: item.merchant ?? "",
                note: item.note
            )
            try store.save(draft, now: date)
        }
    }
}
