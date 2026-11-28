import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("Dışa / içe aktarma (specs/09 §3)")
struct ExchangeStoreTests {
    /// ModelContext kapsayıcısını tutmaz; kapsayıcı bırakılırsa bağlam çöker. Test boyunca burada tutulur.
    private let containers = ContainerBag()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))! }

    private func demoContext() throws -> ModelContext {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        try DemoData.load(into: context, now: now, calendar: calendar)
        return context
    }

    @Test("JSON yedeği yeni kurulmuş depoya geri yüklenince her şey aynı (AC-X4-2)")
    func backupRoundTrip() throws {
        let source = try demoContext()
        let data = try ExchangeStore(context: source).backupJSON(now: now)

        let target = try containers.make()
        try LedgerSeeder.seedIfNeeded(target, locale: Locale(identifier: "tr_TR"))
        try ExchangeStore(context: target).restore(data, mode: .replace)

        func counts(_ context: ModelContext) throws -> [Int] {
            [try context.fetchCount(FetchDescriptor<LedgerAccount>()), try context.fetchCount(FetchDescriptor<LedgerCategory>()),
             try context.fetchCount(FetchDescriptor<LedgerTransaction>()), try context.fetchCount(FetchDescriptor<AssetTrade>()),
             try context.fetchCount(FetchDescriptor<Budget>()), try context.fetchCount(FetchDescriptor<RecurringRule>()),
             try context.fetchCount(FetchDescriptor<PriceSnapshot>()), try context.fetchCount(FetchDescriptor<CustomAsset>())]
        }
        #expect(try counts(target) == counts(source))
        let month = LedgerMonth(year: 2026, month: 11)
        #expect(try LedgerStore(context: target).summary(for: month, currency: .TRY, calendar: calendar)
                == LedgerStore(context: source).summary(for: month, currency: .TRY, calendar: calendar))
        let positions = { (context: ModelContext) in
            try PortfolioStore(context: context, calendar: calendar).positions().map { "\($0.asset.id)=\($0.quantity)" }.sorted()
        }
        #expect(try positions(target) == positions(source))
        // Kart limiti (specs/11 §6) yedekten geri gelir; kalan limit borç ve planlı taksitlerden.
        let card = { (context: ModelContext) in
            try #require(try context.fetch(FetchDescriptor<LedgerAccount>()).first { $0.kind == .card })
        }
        #expect(try card(target).creditLimit == 60_000)
        let available = try #require(try card(source).availableLimit)
        #expect(available < 60_000)
        #expect(try card(target).availableLimit == available)
    }

    @Test("Birleştirme: aynı yedek ikinci kez yüklenince çift kayıt ve çift kategori oluşmaz")
    func mergeIsIdempotent() throws {
        let context = try demoContext()
        let before = try context.fetchCount(FetchDescriptor<LedgerTransaction>())
        let categories = try context.fetchCount(FetchDescriptor<LedgerCategory>())
        let data = try ExchangeStore(context: context).backupJSON(now: now)
        try ExchangeStore(context: context).restore(data, mode: .merge)
        #expect(try context.fetchCount(FetchDescriptor<LedgerTransaction>()) == before)
        #expect(try context.fetchCount(FetchDescriptor<LedgerCategory>()) == categories)
    }

    @Test("Okunamayan ya da daha yeni sürümlü yedek reddedilir, depo değişmez")
    func rejectsBadBackup() throws {
        let context = try demoContext()
        let before = try context.fetchCount(FetchDescriptor<LedgerTransaction>())
        #expect(throws: ExchangeStore.RestoreError.unreadable) {
            try ExchangeStore(context: context).restore(Data("{}".utf8), mode: .replace)
        }
        #expect(try context.fetchCount(FetchDescriptor<LedgerTransaction>()) == before)
    }

    @Test("CSV içe aktarma taslak üretir; aynı dosya ikinci kez alınınca yeni kayıt yok (AC-X4-1)")
    func importDraftsOnce() throws {
        let context = try demoContext()
        let account = try #require(try context.fetch(FetchDescriptor<LedgerAccount>()).first { $0.kind == .bank })
        let table = CSV.decode("""
        Tarih;Açıklama;Tutar
        20.11.2026;MIGROS;-845,20
        21.11.2026;ECZANE;-120,00
        22.11.2026;IADE;50,00
        """)
        let mapping = try #require(CSVImporter.guessMapping(for: table, timeZone: calendar.timeZone))
        let rows = CSVImporter.apply(mapping, to: table, timeZone: calendar.timeZone).rows
        let store = ExchangeStore(context: context)

        let first = try store.importRows(rows, into: account, now: now, calendar: calendar)
        #expect(first == .init(created: 3, duplicates: 0))
        let imported = try context.fetch(FetchDescriptor<LedgerTransaction>()).filter { $0.origin == .import }
        #expect(imported.count == 3)
        #expect(imported.allSatisfy { $0.status == .draft })
        // Satıcı hafızası: "Migros" daha önce Market › Gıda'ya yazılmıştı.
        #expect(imported.first { $0.merchant == "MIGROS" }?.category?.seedKey == "market.food")

        let second = try store.importRows(rows, into: account, now: now, calendar: calendar)
        #expect(second == .init(created: 0, duplicates: 3))
    }

    @Test("CSV dışa aktarma başlık + her işlem bir satır")
    func exportCSV() throws {
        let context = try demoContext()
        let text = try ExchangeStore(context: context).transactionsCSV(locale: Locale(identifier: "tr_TR"), timeZone: calendar.timeZone)
        let rows = CSV.decode(text)
        #expect(rows.count == 1 + (try context.fetchCount(FetchDescriptor<LedgerTransaction>())))
        #expect(rows.dropFirst().contains { $0[8] == "Migros" && $0[6] == "Market" && $0[7] == "Gıda" })
    }
}
