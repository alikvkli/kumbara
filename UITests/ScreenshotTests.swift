import XCTest

/// Örnek veriyle ana ekranların görüntüsünü alır. Yalnız CI'ın ekran görüntüsü işinde çalışır
/// (`TEST_RUNNER_SCREENSHOT_DIR` verildiğinde); normal test koşusunda atlanır.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("SCREENSHOT_DIR verilmedi")
        }
        let suffix = environment["SCREENSHOT_SUFFIX"] ?? "light"
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-demo-data", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()

        func tapTab(_ title: String) {
            let tab = app.tabBars.buttons[title]
            if !tab.waitForExistence(timeout: 3) || !tab.isHittable {
                app.swipeDown()
            }
            tab.tap()
        }

        func shot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.0)
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try data.write(to: output.appendingPathComponent("ios-\(name)-\(suffix).png"))
        }

        XCTAssertTrue(app.buttons["Yeni işlem"].firstMatch.waitForExistence(timeout: 10))
        try shot("1-ozet")

        app.swipeUp()
        try shot("2-ozet-dagilim")

        // Aşağı kaydırınca tab bar küçülür (tabBarMinimizeBehavior); sekmelere dönmek için aç.
        app.swipeDown()
        app.swipeDown()
        tapTab("İşlemler")
        try shot("3-islemler")

        app.buttons["Yeni işlem"].firstMatch.tap()
        let amount = app.textFields["editor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        app.typeText("850")
        let merchant = app.textFields["Satıcı"]
        if merchant.waitForExistence(timeout: 2) {
            merchant.tap()
            app.typeText("Mig")
        }
        try shot("4-yeni-islem")
        app.buttons["Vazgeç"].firstMatch.tap()

        tapTab("Birikim")
        try shot("5-birikim-bos")

        tapTab("Özet")
        app.buttons["Ayarlar"].firstMatch.tap()
        let accounts = app.buttons["Hesaplar"].firstMatch
        if accounts.waitForExistence(timeout: 3) {
            accounts.tap()
            try shot("6-hesaplar")
        }
    }
}
