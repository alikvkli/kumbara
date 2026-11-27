// swift-tools-version: 6.2
import PackageDescription

// KumbaraData: SwiftData modelleri, şema sürümleri, kayıt servisi (specs/05 §2–3).
// Yalnız Apple platformlarında derlenir; iş kuralları KumbaraCore'dadır.
let package = Package(
    name: "KumbaraData",
    defaultLocalization: "tr",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KumbaraData", targets: ["KumbaraData"]),
    ],
    dependencies: [
        .package(path: "../KumbaraCore"),
    ],
    targets: [
        .target(name: "KumbaraData", dependencies: ["KumbaraCore"]),
        .testTarget(name: "KumbaraDataTests", dependencies: ["KumbaraData"]),
    ],
    swiftLanguageModes: [.v6]
)
