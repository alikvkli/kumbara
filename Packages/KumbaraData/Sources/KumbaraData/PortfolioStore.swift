import Foundation
import KumbaraCore
import SwiftData

extension AssetTrade {
    public var asset: AssetCode? { AssetCode(id: assetID) }

    public var trade: Trade? {
        guard let asset, let side = Trade.Side(rawValue: sideRaw),
              let quantity = Decimal(canonical: quantityRaw), let unitPrice = Decimal(canonical: unitPriceRaw),
              let fee = Decimal(canonical: feeRaw)
        else { return nil }
        return Trade(id: id, asset: asset, side: side, quantity: quantity, unitPrice: unitPrice, fee: fee,
                     date: date, usdTRYAtTrade: usdTRYRaw.flatMap { Decimal(canonical: $0) })
    }

    public var draft: TradeDraft? {
        trade.map { TradeDraft(asset: $0.asset, side: $0.side, quantity: $0.quantity, unitPrice: $0.unitPrice,
                               fee: $0.fee, date: $0.date, note: note) }
    }
}

extension CustomAsset {
    public var code: AssetCode { .custom(id.uuidString) }

    public var manualPrice: Decimal? {
        get { manualPriceRaw.flatMap { Decimal(canonical: $0) } }
        set { manualPriceRaw = newValue?.canonicalString }
    }

    /// Elle girilen fiyattan teklif (bid = ask).
    public var quote: Quote? {
        guard let price = manualPrice else { return nil }
        return Quote(asset: code, bid: price, ask: price, asOf: manualPriceDate ?? createdAt, source: .manual)
    }
}

extension PriceSnapshot {
    public var quote: Quote? {
        guard let asset = AssetCode(id: assetID), let source = ProviderID(rawValue: sourceRaw) else { return nil }
        return Quote(asset: asset, bid: bidRaw.flatMap { Decimal(canonical: $0) },
                     ask: askRaw.flatMap { Decimal(canonical: $0) }, asOf: asOf, source: source, isDerived: isDerived)
    }
}

public enum PortfolioStoreError: Error, Equatable {
    case invalid([TradeDraft.Issue])
}

/// Portföy yazma/okuma kapısı (REQ-P1…P8).
@MainActor
public struct PortfolioStore {
    public let context: ModelContext
    public var calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: İşlemler

    public func allTrades() throws -> [AssetTrade] {
        try context.fetch(FetchDescriptor<AssetTrade>(sortBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt)]))
    }

    public func trades(for asset: AssetCode, excluding id: UUID? = nil) throws -> [Trade] {
        let assetID = asset.id
        return try context.fetch(FetchDescriptor<AssetTrade>(predicate: #Predicate { $0.assetID == assetID }))
            .filter { $0.id != id }
            .compactMap(\.trade)
    }

    /// Doğrular ve kaydeder. `usdTRYAtTrade` çağıran tarafından (canlı ya da tarihsel kur) verilir.
    @discardableResult
    public func save(_ draft: TradeDraft, editing: AssetTrade? = nil, usdTRYAtTrade: Decimal?,
                     now: Date = .now) throws -> AssetTrade {
        let existing = try draft.asset.map { try trades(for: $0, excluding: editing?.id) } ?? []
        let issues = draft.issues(existing: existing, now: now)
        guard issues.isEmpty, let trade = draft.trade(id: editing?.id ?? UUID(), usdTRYAtTrade: usdTRYAtTrade) else {
            throw PortfolioStoreError.invalid(issues)
        }
        let record: AssetTrade
        if let editing {
            // `issues(existing:)` düzenlenen kayıt hariç tüm seriyi yeni değerle doğruladı.
            editing.apply(trade)
            editing.note = draft.note
            record = editing
        } else {
            record = AssetTrade(trade: trade, note: draft.note)
            context.insert(record)
        }
        try context.save()
        return record
    }

    /// Silme, sonraki satışları geçersiz kılacaksa (fazla satış) reddedilir.
    public func delete(_ record: AssetTrade) throws {
        if let asset = record.asset {
            let remaining = try trades(for: asset, excluding: record.id)
            _ = try Position(asset: asset, trades: remaining)
        }
        context.delete(record)
        try context.save()
    }

    // MARK: Pozisyonlar

    /// Açık ve kapanmış tüm pozisyonlar.
    public func positions(method: CostMethod = .averageCost) throws -> [Position] {
        let grouped = Dictionary(grouping: try allTrades().compactMap(\.trade), by: \.asset)
        return try grouped.map { try Position(asset: $0.key, trades: $0.value, method: method) }
            .sorted { $0.asset.id < $1.asset.id }
    }

    public func heldAssets() throws -> Set<AssetCode> {
        Set(try positions().filter(\.isOpen).map(\.asset))
    }

    // MARK: Fiyatlar (specs/02 §6)

    /// Gelen fiyatları günlük kayda yazar: aynı gün için daha yeni fiyat öncekini ezer.
    public func record(_ quotes: some Sequence<Quote>) throws {
        for quote in quotes {
            let day = calendar.startOfDay(for: quote.asOf)
            let assetID = quote.asset.id
            var descriptor = FetchDescriptor<PriceSnapshot>(predicate: #Predicate { $0.assetID == assetID && $0.day == day })
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                if existing.asOf <= quote.asOf { existing.apply(quote) }
            } else {
                context.insert(PriceSnapshot(quote: quote, day: day))
            }
        }
        if context.hasChanges { try context.save() }
    }

    /// Her varlığın son bilinen fiyatı (çevrimdışı açılış, C4). Serbest varlıklar elle fiyatlarıyla.
    public func latestQuotes() throws -> [AssetCode: Quote] {
        var result: [AssetCode: Quote] = [:]
        for snapshot in try context.fetch(FetchDescriptor<PriceSnapshot>(sortBy: [SortDescriptor(\.asOf)])) {
            if let quote = snapshot.quote { result[quote.asset] = quote }
        }
        for custom in try context.fetch(FetchDescriptor<CustomAsset>()) {
            if let quote = custom.quote { result[custom.code] = quote }
        }
        return result
    }

    /// Grafik için günlük fiyatlar (seçilen fiyat tipiyle).
    public func priceHistory(priceKind: PriceKind) throws -> [AssetCode: [(date: Date, price: Decimal)]] {
        var result: [AssetCode: [(date: Date, price: Decimal)]] = [:]
        for snapshot in try context.fetch(FetchDescriptor<PriceSnapshot>(sortBy: [SortDescriptor(\.day)])) {
            guard let quote = snapshot.quote else { continue }
            result[quote.asset, default: []].append((snapshot.day, quote.price(priceKind)))
        }
        return result
    }

    public func customAssets() throws -> [CustomAsset] {
        try context.fetch(FetchDescriptor<CustomAsset>(sortBy: [SortDescriptor(\.name)]))
    }
}
