// swift-tools-version: 6.2
import PackageDescription

// KumbaraCore: saf Swift iş kuralları (specs/00 C7, specs/05 §2).
// Foundation dışında bağımlılık yok; Linux'ta da derlenir ve test edilir.
let package = Package(
    name: "KumbaraCore",
    defaultLocalization: "tr",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KumbaraCore", targets: ["KumbaraCore"]),
    ],
    targets: [
        .target(name: "KumbaraCore"),
        .testTarget(name: "KumbaraCoreTests", dependencies: ["KumbaraCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
