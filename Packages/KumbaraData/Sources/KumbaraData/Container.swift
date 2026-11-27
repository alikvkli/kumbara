import Foundation
import KumbaraCore
import SwiftData

public enum KumbaraContainer {
    /// Uygulamanın kalıcı deposu. iCloud eşitleme M5'te (REQ-X2) opsiyonel olarak açılır.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        // Bellek içi depolar (test, UI testi) birbirine karışmasın diye her biri ayrı adla açılır.
        let name = inMemory ? "Kumbara-\(UUID().uuidString)" : "Kumbara"
        let configuration = ModelConfiguration(name, schema: schema,
                                               isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: KumbaraMigrationPlan.self,
                                  configurations: configuration)
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
