import Foundation
import KumbaraCore
import KumbaraData
import KumbaraMarket
import Observation
import SwiftData

/// Uygulamanın tek fiyat kaynağı (specs/02, C4). Açılışta diskteki son fiyatlarla dolar,
/// uygulama ön plandayken 60 sn'de bir yenilenir; gelen fiyatlar günlük kayda yazılır.
@MainActor
@Observable
final class PriceBoard {
    private(set) var quotes: [AssetCode: Quote] = [:]
    private(set) var lastAttempt: Date?
    private(set) var lastSuccess: Date?
    private(set) var isRefreshing = false
    /// Son yenilemede hiçbir kaynaktan alınamayan veya reddedilen varlıklar.
    private(set) var unavailable: Set<AssetCode> = []
    /// Son yenilemede ağa hiç ulaşılamadı mı.
    private(set) var isOffline = false

    /// Alt aksesuar ve piyasa sayfasında her zaman gösterilenler.
    static let tickerAssets: [AssetCode] = [.gold(.gram24), .fx(.USD), .fx(.EUR)]
    static let marketAssets: [AssetCode] = GoldKind.allCases.map { .gold($0) }
        + PreciousMetal.allCases.map { .metal($0) } + [.fx(.USD), .fx(.EUR), .fx(.GBP), .fx(.CHF)]

    /// Görünür ekranların istediği ek varlıklar (ör. piyasa sayfası). Periyodik yenilemeye de girer.
    private var watched: [UUID: Set<AssetCode>] = [:]
    /// Yenileme sürerken gelen istekler; bitince hemen bir tur daha atılır (istek kaybolmaz).
    private var pending: Set<AssetCode>?

    private let service: MarketService
    private let container: ModelContainer
    private let calendar: Calendar

    init(container: ModelContainer, service: MarketService = MarketService(), calendar: Calendar = .current) {
        self.container = container
        self.service = service
        self.calendar = calendar
        loadCached()
    }

    private var store: PortfolioStore { PortfolioStore(context: container.mainContext, calendar: calendar) }

    func quote(_ asset: AssetCode) -> Quote? { quotes[asset] }

    func freshness(of asset: AssetCode, now: Date = .now) -> Freshness? {
        quotes[asset].map { Freshness.evaluate(asOf: $0.asOf, now: now, calendar: calendar) }
    }

    /// Diskteki son fiyatlar (çevrimdışı açılış).
    func loadCached() {
        let cached = (try? store.latestQuotes()) ?? [:]
        quotes.merge(cached) { current, stored in current.asOf >= stored.asOf ? current : stored }
        let seed = Array(cached.values)
        Task { await service.seed(seed) }
    }

    /// Ekran görünürken `assets` periyodik yenilemeye katılır; dönen kimlikle bırakılır.
    func watch(_ assets: Set<AssetCode>) -> UUID {
        let token = UUID()
        watched[token] = assets
        return token
    }

    func unwatch(_ token: UUID) { watched[token] = nil }

    func refresh(including extra: Set<AssetCode> = []) async {
        guard !isRefreshing else {
            // Kaybolmasın: mevcut tur bitince bu varlıklarla bir tur daha.
            pending = (pending ?? []).union(extra)
            return
        }
        isRefreshing = true
        await performRefresh(including: extra)
        while let next = pending {
            pending = nil
            await performRefresh(including: next)
        }
        isRefreshing = false
    }

    private func performRefresh(including extra: Set<AssetCode>) async {
        let held = (try? store.heldAssets()) ?? []
        let alerted = (try? PriceAlertStore(context: container.mainContext).activeAssets()) ?? []
        let wanted = held.union(Self.tickerAssets).union(extra).union(watched.values.flatMap { $0 }).union(alerted)
        let result = await service.refresh(wanted)

        lastAttempt = .now
        if !result.quotes.isEmpty { lastSuccess = .now }
        isOffline = result.quotes.isEmpty && !result.failedProviders.isEmpty
        unavailable = result.missing.union(result.rejected)
        for (asset, quote) in result.quotes { quotes[asset] = quote }
        try? store.record(result.quotes.values)
        // Fiyat alarmları her başarılı yenilemede (ön planda 60 sn, arka planda fırsat buldukça) (REQ-M4).
        if let fired = try? PriceAlertStore(context: container.mainContext).evaluate(result.quotes) {
            for (alert, quote) in fired { Reminders.priceAlertFired(alert, quote: quote) }
        }
        // Serbest varlıklar elle fiyatlarıyla (kullanıcı güncellemiş olabilir).
        for (asset, quote) in (try? store.latestQuotes()) ?? [:] where quote.source == .manual {
            quotes[asset] = quote
        }
    }

    /// Ön plandayken periyodik yenileme (REQ-M2). Görev iptal edilince durur.
    func runWhileActive(interval: Duration = .seconds(60), including extra: Set<AssetCode> = []) async {
        while !Task.isCancelled {
            await refresh(including: extra)
            try? await Task.sleep(for: interval)
        }
    }

    /// Geçmiş tarihli alımlar için USD/TRY (reel getiri). Bugünse canlı kur.
    func usdTRY(on date: Date) async -> Decimal? {
        if calendar.isDateInToday(date) { return quotes[.fx(.USD)]?.price(.ask) }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return try? await service.usdTRY(year: year, month: month, day: day)
    }

    /// Serbest varlığın fiyatı değişince panoya yansıt.
    func reloadManualQuotes() {
        for (asset, quote) in (try? store.latestQuotes()) ?? [:] where quote.source == .manual {
            quotes[asset] = quote
        }
    }
}
