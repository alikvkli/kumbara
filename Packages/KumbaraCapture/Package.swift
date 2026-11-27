// swift-tools-version: 6.2
import PackageDescription

// KumbaraCapture: Vision / PDFKit sarmalayıcıları → [TextLine] (specs/04 §2.1, specs/05 §2).
// Ayrıştırma KumbaraCore'dadır. Tamamen cihaz üstü (C2).
let package = Package(
    name: "KumbaraCapture",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KumbaraCapture", targets: ["KumbaraCapture"]),
    ],
    dependencies: [
        .package(path: "../KumbaraCore"),
    ],
    targets: [
        .target(name: "KumbaraCapture", dependencies: ["KumbaraCore"]),
    ],
    swiftLanguageModes: [.v6]
)
