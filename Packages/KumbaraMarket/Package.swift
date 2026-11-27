// swift-tools-version: 6.2
import PackageDescription

// KumbaraMarket: piyasa verisi ağ katmanı ve yedekleme zinciri (specs/02, specs/05 §2).
// Ayrıştırma ve politikalar KumbaraCore'da; burada yalnız istek, sıra ve durum.
let package = Package(
    name: "KumbaraMarket",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KumbaraMarket", targets: ["KumbaraMarket"]),
    ],
    dependencies: [
        .package(path: "../KumbaraCore"),
    ],
    targets: [
        .target(name: "KumbaraMarket", dependencies: ["KumbaraCore"]),
        .testTarget(name: "KumbaraMarketTests", dependencies: ["KumbaraMarket"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
