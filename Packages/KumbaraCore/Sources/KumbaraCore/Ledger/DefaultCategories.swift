import Foundation

/// İlk açılışta oluşturulan kategori seti (REQ-L5). İki seviyeli; kullanıcı düzenleyebilir.
///
/// `key` kalıcıdır (seed tekrarında ve iCloud birleştirmede tekilleştirme için); değiştirilmez.
/// `symbol` SF Symbols adıdır; alt kategori `nil` ise üstünkünü kullanır.
public struct CategorySeed: Hashable, Sendable {
    public var key: String
    public var kind: CategoryKind
    public var nameTR: String
    public var nameEN: String
    public var symbol: String?
    public var color: CategoryColor
    public var children: [CategorySeed]

    public func name(for locale: Locale) -> String {
        locale.language.languageCode?.identifier == "tr" ? nameTR : nameEN
    }
}

public enum DefaultCategories {
    private static func c(_ key: String, _ kind: CategoryKind, _ tr: String, _ en: String,
                          _ symbol: String?, _ color: CategoryColor, _ children: [CategorySeed] = []) -> CategorySeed {
        CategorySeed(key: key, kind: kind, nameTR: tr, nameEN: en, symbol: symbol, color: color, children: children)
    }

    private static func sub(_ key: String, _ kind: CategoryKind, _ tr: String, _ en: String,
                            _ color: CategoryColor, symbol: String? = nil) -> CategorySeed {
        CategorySeed(key: key, kind: kind, nameTR: tr, nameEN: en, symbol: symbol, color: color, children: [])
    }

    public static let expense: [CategorySeed] = [
        c("market", .expense, "Market", "Groceries", "cart", .green, [
            sub("market.food", .expense, "Gıda", "Food", .green),
            sub("market.household", .expense, "Ev ve temizlik", "Household", .green),
        ]),
        c("dining", .expense, "Yeme-içme", "Dining", "fork.knife", .orange, [
            sub("dining.restaurant", .expense, "Restoran", "Restaurants", .orange),
            sub("dining.cafe", .expense, "Kafe", "Cafés", .orange, symbol: "cup.and.saucer"),
            sub("dining.delivery", .expense, "Paket servis", "Delivery", .orange, symbol: "takeoutbag.and.cup.and.straw"),
        ]),
        c("transport", .expense, "Ulaşım", "Transport", "car", .indigo, [
            sub("transport.fuel", .expense, "Yakıt", "Fuel", .indigo, symbol: "fuelpump"),
            sub("transport.public", .expense, "Toplu taşıma", "Public transit", .indigo, symbol: "tram"),
            sub("transport.taxi", .expense, "Taksi", "Taxi", .indigo),
            sub("transport.tolls", .expense, "Otopark ve otoyol", "Parking & tolls", .indigo, symbol: "parkingsign"),
        ]),
        c("housing", .expense, "Konut", "Housing", "house", .brown, [
            sub("housing.rent", .expense, "Kira", "Rent", .brown),
            sub("housing.dues", .expense, "Aidat", "HOA dues", .brown),
            sub("housing.electricity", .expense, "Elektrik", "Electricity", .brown, symbol: "bolt"),
            sub("housing.gas", .expense, "Doğalgaz", "Natural gas", .brown, symbol: "flame"),
            sub("housing.water", .expense, "Su", "Water", .brown, symbol: "drop"),
            sub("housing.internet", .expense, "İnternet ve telefon", "Internet & phone", .brown, symbol: "wifi"),
        ]),
        c("health", .expense, "Sağlık", "Health", "cross.case", .teal, [
            sub("health.pharmacy", .expense, "Eczane", "Pharmacy", .teal, symbol: "pills"),
            sub("health.doctor", .expense, "Doktor", "Doctor", .teal, symbol: "stethoscope"),
        ]),
        c("subscriptions", .expense, "Abonelikler", "Subscriptions", "repeat", .purple),
        c("clothing", .expense, "Giyim", "Clothing", "tshirt", .mint),
        c("education", .expense, "Eğitim", "Education", "book", .teal),
        c("entertainment", .expense, "Eğlence", "Entertainment", "theatermasks", .purple),
        c("personal", .expense, "Kişisel bakım", "Personal care", "scissors", .mint),
        c("gifts", .expense, "Hediye", "Gifts", "gift", .orange),
        c("other.expense", .expense, "Diğer", "Other", "ellipsis.circle", .gray),
    ]

    public static let income: [CategorySeed] = [
        c("salary", .income, "Maaş", "Salary", "banknote", .green),
        c("freelance", .income, "Ek gelir", "Side income", "briefcase", .teal),
        c("rental", .income, "Kira geliri", "Rental income", "house", .brown),
        c("interest", .income, "Faiz ve getiri", "Interest & returns", "percent", .indigo),
        c("gifts.income", .income, "Hediye", "Gifts", "gift", .orange),
        c("other.income", .income, "Diğer", "Other", "ellipsis.circle", .gray),
    ]

    public static var all: [CategorySeed] { expense + income }

    /// Tüm anahtarlar (alt kategoriler dahil).
    public static var allKeys: [String] {
        all.flatMap { [$0.key] + $0.children.map(\.key) }
    }
}
