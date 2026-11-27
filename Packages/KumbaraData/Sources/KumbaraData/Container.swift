import Foundation
import KumbaraCore
import SwiftData

public enum KumbaraContainer {
    /// Uygulama, paylaş uzantısı ve widget'ların ortak kapsayıcısı (specs/09 §0).
    public static let appGroup = CaptureInbox.appGroup
    static let storeName = "Kumbara"
    /// CloudKit kapsayıcısı (REQ-X2, specs/09 §1). Etkinleştirme: README › "iCloud eşitlemeyi açma".
    public static let cloudContainer = "iCloud.com.alikvkli.kumbara"

    /// Uygulamanın kalıcı deposu. App Group kapsayıcısında durur ki widget'lar ve kontroller aynı
    /// veriyi okuyabilsin; kapsayıcı yoksa (imzasız derleme) uygulamanın kendi klasörüne düşer.
    ///
    /// `iCloudSync`: aynı yerel depo kullanıcının özel iCloud veritabanıyla eşitlenir (varsayılan kapalı).
    /// Uygulama iCloud yetkisiyle imzalanmadıysa açılmamalıdır; çağıran taraf bunu derleme bayrağıyla
    /// (`ICLOUD`) güvenceye alır.
    public static func make(inMemory: Bool = false, iCloudSync: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            // Bellek içi depolar (test, UI testi) birbirine karışmasın diye her biri ayrı adla açılır.
            configuration = ModelConfiguration("Kumbara-\(UUID().uuidString)", schema: schema,
                                               isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let url = try storeURL()
            configuration = ModelConfiguration(storeName, schema: schema, url: url,
                                               cloudKitDatabase: iCloudSync ? .private(cloudContainer) : .none)
        }
        return try ModelContainer(for: schema, migrationPlan: KumbaraMigrationPlan.self,
                                  configurations: configuration)
    }

    /// Deponun yeri. App Group varsa oradadır; eski (uygulama klasöründeki) depo varsa bir kez taşınır.
    static func storeURL(fileManager: FileManager = .default) throws -> URL {
        let legacyDirectory = URL.applicationSupportDirectory
        guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
            return legacyDirectory.appending(path: "\(storeName).store")
        }
        let directory = group.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try moveLegacyStore(from: legacyDirectory, to: directory, fileManager: fileManager)
        return directory.appending(path: "\(storeName).store")
    }

    /// Eski depoyu (ana dosya + `-wal`, `-shm`) yeni klasöre taşır. Hedefte depo varsa dokunmaz
    /// (veri asla üzerine yazılmaz); kaynakta yoksa bir şey yapmaz.
    static func moveLegacyStore(from source: URL, to destination: URL, fileManager: FileManager = .default) throws {
        let main = "\(storeName).store"
        guard fileManager.fileExists(atPath: source.appending(path: main).path),
              !fileManager.fileExists(atPath: destination.appending(path: main).path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let from = source.appending(path: main + suffix)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try fileManager.moveItem(at: from, to: destination.appending(path: main + suffix))
        }
    }
}

/// İlk açılış verisi (REQ-L5): varsayılan kategoriler ve bir "Nakit" hesabı.
/// Tekrar çağrılması güvenlidir; mevcut seed anahtarları yeniden oluşturulmaz.
@MainActor
public enum LedgerSeeder {
    public static func seedIfNeeded(_ context: ModelContext, locale: Locale = .current) throws {
        let existingKeys = Set(try context.fetch(FetchDescriptor<LedgerCategory>()).compactMap(\.seedKey))

        for (index, seed) in DefaultCategories.all.enumerated() where !existingKeys.contains(seed.key) {
            let parent = LedgerCategory(name: seed.name(for: locale), kind: seed.kind, symbol: seed.symbol ?? "",
                                        color: seed.color, seedKey: seed.key, sortIndex: index)
            context.insert(parent)
            for (childIndex, child) in seed.children.enumerated() where !existingKeys.contains(child.key) {
                context.insert(LedgerCategory(name: child.name(for: locale), kind: child.kind,
                                              symbol: child.symbol ?? "", color: child.color,
                                              parent: parent, seedKey: child.key, sortIndex: childIndex))
            }
        }

        if try context.fetchCount(FetchDescriptor<LedgerAccount>()) == 0 {
            let name = locale.language.languageCode?.identifier == "tr" ? "Nakit" : "Cash"
            context.insert(LedgerAccount(name: name, kind: .cash, currency: .TRY))
        }

        if context.hasChanges { try context.save() }
    }
}
