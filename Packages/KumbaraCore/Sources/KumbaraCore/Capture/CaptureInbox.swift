import Foundation

/// Paylaş uzantısı → uygulama gelen kutusu (REQ-C2, specs/05 §4).
///
/// Uzantı ağır iş yapmaz (bellek sınırı): paylaşılan görüntü/PDF'i App Group'taki `Inbox/` klasörüne
/// yazar ve kapanır. Uygulama öne gelince dosyaları sırayla OCR'dan geçirip onay ekranını açar;
/// dosya, onay ekranı kapanınca (kaydedilse de vazgeçilse de) silinir.
///
/// Yazım atomiktir: önce gizli `.partial` dosyasına yazılır, sonra yeniden adlandırılır. Uygulama
/// yarım yazılmış bir dosyayı hiçbir zaman görmez.
public struct CaptureInbox: Sendable {
    public struct Item: Hashable, Sendable {
        public let url: URL
        public let createdAt: Date
        public var fileExtension: String { url.pathExtension.lowercased() }
    }

    public enum DepositError: Error, Equatable {
        case empty, tooLarge, unsupported
    }

    /// Tek dosya üst sınırı: telefon fotoğrafı ve çok sayfalı e-arşiv PDF'i için bol.
    public static let maxBytes = 25 * 1024 * 1024
    /// Unutulmuş paylaşımlar birikmesin: en eskiler atılır.
    public static let maxItems = 20
    static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "pdf"]

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    @discardableResult
    public func deposit(_ data: Data, fileExtension: String, now: Date = .now) throws -> Item {
        let ext = fileExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else { throw DepositError.unsupported }
        guard !data.isEmpty else { throw DepositError.empty }
        guard data.count <= Self.maxBytes else { throw DepositError.tooLarge }

        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let millis = Int64((now.timeIntervalSince1970 * 1000).rounded())
        let name = "\(millis)-\(UUID().uuidString)"
        let partial = directory.appendingPathComponent(".\(name).partial")
        let final = directory.appendingPathComponent(name).appendingPathExtension(ext)
        try data.write(to: partial)
        try files.moveItem(at: partial, to: final)
        trim(now: now)
        return Item(url: final, createdAt: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    /// Bekleyen dosyalar, en eskiden yeniye.
    public func pending() -> [Item] {
        // Adlardan, kendi klasörümüze göre kurulur: macOS'ta /var → /private/var gibi bağlantılar
        // çözülürse `deposit` ile dönen URL'lerle eşitlik bozulmasın.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.map { directory.appendingPathComponent($0) }.compactMap(Self.item(at:))
            .sorted { ($0.createdAt, $0.url.lastPathComponent) < ($1.createdAt, $1.url.lastPathComponent) }
    }

    public func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
    }

    /// Fazlalık (en eskiler) ve 1 saatten eski yarım yazımlar silinir.
    func trim(now: Date) {
        let files = FileManager.default
        let urls = ((try? files.contentsOfDirectory(atPath: directory.path)) ?? []).map { directory.appendingPathComponent($0) }
        for url in urls where url.lastPathComponent.hasPrefix(".") && url.pathExtension == "partial" {
            let millis = Int64(url.lastPathComponent.dropFirst().prefix { $0 != "-" }) ?? 0
            if now.timeIntervalSince1970 - Double(millis) / 1000 > 3600 { try? files.removeItem(at: url) }
        }
        for item in pending().dropLast(Self.maxItems) { remove(item) }
    }

    private static func item(at url: URL) -> Item? {
        let name = url.lastPathComponent
        guard !name.hasPrefix("."), allowedExtensions.contains(url.pathExtension.lowercased()),
              let millis = Int64(name.prefix { $0 != "-" }) else { return nil }
        return Item(url: url, createdAt: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
}

#if canImport(Darwin)
extension CaptureInbox {
    /// specs/open-questions D9. İmzalı derlemede iki hedefte de bu App Group yetkisi olmalı (Q10: Team ID).
    public static let appGroup = "group.com.alikvkli.kumbara"

    /// Uygulama ile paylaş uzantısının ortak gelen kutusu; App Group yoksa `nil`.
    public static func shared() -> CaptureInbox? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        return CaptureInbox(directory: container.appendingPathComponent("Inbox", isDirectory: true))
    }
}
#endif
