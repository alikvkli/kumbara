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
        // Abonelik geçmişi (specs/10 §2): Netflix bu ay zamlandı, Spotify bu ay görünmedi.
        Item(monthOffset: -3, day: 5, kind: .expense, amount: "189.99", account: "card", category: "subscriptions", merchant: "Netflix"),
        Item(monthOffset: -2, day: 5, kind: .expense, amount: "189.99", account: "card", category: "subscriptions", merchant: "Netflix"),
        Item(monthOffset: -1, day: 5, kind: .expense, amount: "189.99", account: "card", category: "subscriptions", merchant: "Netflix"),
        Item(monthOffset: -3, day: 12, kind: .expense, amount: "99", account: "card", category: "subscriptions", merchant: "Spotify"),
        Item(monthOffset: -2, day: 12, kind: .expense, amount: "99", account: "card", category: "subscriptions", merchant: "Spotify"),
        Item(monthOffset: -1, day: 12, kind: .expense, amount: "99", account: "card", category: "subscriptions", merchant: "Spotify"),
        // İki ay önce (rapor karşılaştırması için)
        Item(monthOffset: -2, day: 1, kind: .income, amount: "62000", account: "bank", category: "salary", merchant: nil),
        Item(monthOffset: -2, day: 1, kind: .expense, amount: "22500", account: "bank", category: "housing.rent", merchant: nil),
        Item(monthOffset: -2, day: 7, kind: .expense, amount: "3105.30", account: "card", category: "market.food", merchant: "Migros"),
        Item(monthOffset: -2, day: 9, kind: .expense, amount: "2450", account: "card", category: "transport.fuel", merchant: "Opet"),
        Item(monthOffset: -2, day: 15, kind: .expense, amount: "1650", account: "card", category: "dining.restaurant", merchant: "Köfteci Yusuf"),
        // Geçen ay (karşılaştırma için)
        Item(monthOffset: -1, day: 1, kind: .income, amount: "62000", account: "bank", category: "salary", merchant: nil),
        Item(monthOffset: -1, day: 1, kind: .expense, amount: "22500", account: "bank", category: "housing.rent", merchant: nil),
        Item(monthOffset: -1, day: 6, kind: .expense, amount: "3420.60", account: "card", category: "market.food", merchant: "Migros"),
        Item(monthOffset: -1, day: 9, kind: .expense, amount: "2600", account: "card", category: "transport.fuel", merchant: "Opet"),
        Item(monthOffset: -1, day: 15, kind: .expense, amount: "1940", account: "card", category: "dining.restaurant", merchant: "Köfteci Yusuf"),
        Item(monthOffset: -1, day: 21, kind: .expense, amount: "2875.40", account: "card", category: "market.food", merchant: "CarrefourSA"),
        Item(monthOffset: -1, day: 1, kind: .expense, amount: "900", account: "card", category: "personal", merchant: "MacFit"),
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
        card.statementDay = 15
        card.paymentDueDay = 25
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
            var month = thisMonth
            for _ in 0..<(-item.monthOffset) { month = month.previous }
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
        // Bütçeler: genel (~%80), market (uyarı), yeme-içme (normal), ulaşım (aşıldı).
        let budgets = BudgetStore(context: context)
        try budgets.setLimit(45_000, for: nil, from: thisMonth.previous)
        for (key, limit) in [("market", Decimal(4500)), ("dining", 2000), ("transport", 4000)] {
            if let category = categories[key] { try budgets.setLimit(limit, for: category, from: thisMonth.previous) }
        }
        // Tekrarlayanlar: kira (bu ayınki zaten girili, kurala bağlanır) ve spor salonu (bu ay onay bekler).
        let recurring = RecurringStore(context: context)
        let all = try context.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date)]))
        if let gym = all.first(where: { $0.merchant == "MacFit" }) {
            try recurring.makeRule(from: gym, frequency: .monthly(day: 1), calendar: calendar)
        }
        let rents = all.filter { $0.category?.seedKey == "housing.rent" }
        if let first = rents.first {
            let rule = try recurring.makeRule(from: first, frequency: .monthly(day: 1), calendar: calendar)
            for rent in rents.dropFirst() {
                rent.recurrenceID = rule.id
                rent.dueDay = calendar.startOfDay(for: rent.date)
            }
        }
        // Maaş da tekrarlayan gelir: ödeme takviminde "maaşa N gün" (specs/10 §5).
        let salaries = all.filter { $0.category?.seedKey == "salary" }
        if let first = salaries.first {
            let rule = try recurring.makeRule(from: first, frequency: .monthly(day: 1), calendar: calendar)
            for salary in salaries.dropFirst() {
                salary.recurrenceID = rule.id
                salary.dueDay = calendar.startOfDay(for: salary.date)
            }
            rule.lastDue = salaries.last.map { calendar.startOfDay(for: $0.date) }
        }
        let rentRules = try recurring.rules().filter { $0.category?.seedKey == "housing.rent" }
        for rule in rentRules { rule.lastDue = rents.last.map { calendar.startOfDay(for: $0.date) } }
        try recurring.generateDrafts(now: now, calendar: calendar)
        // Taksitli alım: geçen ayın 10'unda ₺12.000, 6 taksit (2'si kesin, 4'ü planlı).
        if let date = calendar.date(from: DateComponents(year: thisMonth.previous.year, month: thisMonth.previous.month, day: 10, hour: 16)),
           let electronics = categories["entertainment"] {
            try InstallmentStore(context: context).save(
                TransactionDraft(amount: 12_000, date: date, account: card.ref, category: electronics.ref, merchant: "MediaMarkt"),
                count: 6, now: now, calendar: calendar)
        }
        // Kart ödemesi: son ekstre son ödeme gününden 2 gün önce maaş hesabından tam ödenmiş olsun
        // (ekran görüntüleri gecikmiş borç göstermesin).
        let installments = InstallmentStore(context: context)
        if let statement = try installments.statement(for: card, now: now, calendar: calendar),
           statement.remainingDue.amount > 0,
           let paid = calendar.date(byAdding: .day, value: -2, to: statement.last.due),
           paid > statement.last.closing, paid <= now {
            try store.save(TransactionDraft(kind: .transfer, amount: statement.remainingDue.amount,
                                            date: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: paid) ?? paid,
                                            account: bank.ref, toAccount: card.ref), now: now)
        }
        try loadPortfolio(into: context, now: now, calendar: calendar)
    }

    /// Birikim örneği: gram altın, çeyrek, USD ve bir serbest fon; son 210 gün için **yapay**
    /// günlük fiyat geçmişi (grafik görünsün diye). Güncel fiyat uygulama açılınca gerçek kaynaktan gelir.
    private static func loadPortfolio(into context: ModelContext, now: Date, calendar: Calendar) throws {
        let store = PortfolioStore(context: context, calendar: calendar)
        func ago(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!.addingTimeInterval(12 * 3600)
        }
        func dec(_ s: String) -> Decimal { Decimal(canonical: s)! }

        let fund = CustomAsset(name: "Para piyasası fonu")
        fund.manualPrice = dec("1.4218")
        fund.manualPriceDate = ago(1)
        context.insert(fund)
        try context.save()

        let trades: [(AssetCode, Trade.Side, String, String, String, Int, String)] = [
            (.fx(.USD), .buy, "1200", "41.20", "0", 200, "41.20"),
            (.gold(.gram24), .buy, "10", "4985", "0", 150, "41.85"),
            (.gold(.quarter), .buy, "4", "8650", "0", 120, "43.10"),
            (fund.code, .buy, "10000", "1.18", "0", 90, "45.30"),
            (.gold(.gram24), .buy, "5", "5420", "120", 60, "47.40"),
            (.gold(.quarter), .buy, "4", "9380", "0", 45, "48.60"),
            (.gold(.gram24), .buy, "2.5", "5810", "0", 10, "50.55"),
        ]
        var saved: [AssetTrade] = []
        for (asset, side, quantity, price, fee, daysAgo, usd) in trades {
            saved.append(try store.save(TradeDraft(asset: asset, side: side, quantity: dec(quantity), unitPrice: dec(price),
                                                   fee: dec(fee), date: ago(daysAgo)), usdTRYAtTrade: dec(usd), now: now))
        }

        // Hedefler: çeyreklerin hepsi düğün için (8 / 20); gram altınlar ev peşinatı için.
        let goals = GoalStore(context: context)
        let wedding = try goals.save(SavingsGoal(name: "Düğün", target: .quantity(.gold(.quarter), 20),
                                                 deadline: calendar.date(byAdding: .month, value: 10, to: now)))
        let home = try goals.save(SavingsGoal(name: "Ev peşinatı", target: .amount(500_000),
                                              deadline: calendar.date(byAdding: .month, value: 24, to: now)))
        try goals.assign(saved.filter { $0.asset == .gold(.quarter) }, to: wedding)
        try goals.assign(saved.filter { $0.asset == .gold(.gram24) }, to: home)

        // Birikim planı (specs/10 §7): her ay son gram alımının gününde 2,5 gram, ev peşinatı için.
        let planDay = calendar.component(.day, from: ago(10))
        try PlanStore(context: context).save(SavingsPlanRule(
            asset: .gold(.gram24), target: .quantity(dec("2.5")), trigger: .schedule(.monthly(day: planDay)),
            start: calendar.startOfDay(for: ago(70)), goalID: home.id))

        // Yapay fiyat eğrisi: doğrusal yükseliş + hafif dalga; bugün gerçek düzeye yakın biter.
        let curves: [(AssetCode, Double, Double, Double)] = [
            (.gold(.gram24), 4_850, 5_925, 0.012),
            (.gold(.quarter), 8_400, 9_975, 0.012),
            (.fx(.USD), 41.0, 50.75, 0.002),
        ]
        var quotes: [Quote] = []
        for daysAgo in stride(from: 210, through: 1, by: -1) {
            let t = Double(210 - daysAgo) / 209
            for (asset, start, end, wobble) in curves {
                let base = start + (end - start) * t
                let value = base * (1 + wobble * sin(Double(daysAgo) / 9))
                let rounded = (value * 100).rounded() / 100
                let spread = asset == .gold(.quarter) ? 0.024 : 0.0015
                if let quote = Quote(asset: asset, bid: Decimal(string: String(format: "%.2f", rounded))!,
                                     ask: Decimal(string: String(format: "%.2f", rounded * (1 + spread)))!,
                                     asOf: ago(daysAgo), source: .truncgil) {
                    quotes.append(quote)
                }
            }
        }
        try store.record(quotes)
    }
}
