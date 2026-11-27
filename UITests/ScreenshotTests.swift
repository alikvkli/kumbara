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
        Thread.sleep(forTimeInterval: 3) // canlı fiyatlar gelsin
        try shot("5-birikim")

        // Hedefler grafiğin altında: kaydır, hedefleri çek; varlıklar onların altında.
        app.swipeUp()
        try shot("5b-hedefler")
        let gram = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Gram altın")).firstMatch
        if !gram.isHittable { app.swipeUp() }
        if gram.waitForExistence(timeout: 3) {
            gram.tap()
            try shot("6-gram-altin")
            app.swipeUp()
            try shot("6b-gram-reel-getiri")
            app.swipeDown()
            let bell = app.buttons["Alarm kur"].firstMatch
            if bell.waitForExistence(timeout: 2) {
                bell.tap()
                if app.textFields["alert.threshold"].waitForExistence(timeout: 3) {
                    try shot("14-alarm")
                    app.buttons["Vazgeç"].firstMatch.tap()
                }
            }
            app.navigationBars.buttons.firstMatch.tap()
        }

        let ticker = app.buttons["Piyasa fiyatları"].firstMatch
        if ticker.waitForExistence(timeout: 3) {
            ticker.tap()
            // Tüm piyasa fiyatlarının gelmesini bekle (ağ hızına bağlı; sabit süre yetmiyor).
            let updated = app.staticTexts["Güncellendi"].firstMatch
            _ = updated.waitForExistence(timeout: 20)
            let loading = NSPredicate(format: "label == %@", "Yükleniyor")
            let deadline = Date.now.addingTimeInterval(20)
            while app.staticTexts.matching(loading).count > 0, Date.now < deadline {
                Thread.sleep(forTimeInterval: 0.5)
            }
            Thread.sleep(forTimeInterval: 1)
            try shot("7-piyasa")
            let fx = app.buttons["Döviz"].firstMatch
            if fx.waitForExistence(timeout: 2) {
                fx.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("7b-piyasa-doviz")
                app.buttons["Altın"].firstMatch.tap()
            }
            app.buttons["Bitti"].firstMatch.tap()
        }

        tapTab("Bütçe")
        if app.staticTexts["Kategoriler"].firstMatch.waitForExistence(timeout: 5) {
            try shot("10-butce")
            let market = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Market")).firstMatch
            if market.waitForExistence(timeout: 3) {
                market.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("12-butce-detay")
                app.navigationBars.buttons.firstMatch.tap()
            }
            app.buttons["Bütçe ekle"].firstMatch.tap()
            if app.textFields["budget.limit"].waitForExistence(timeout: 3) {
                try shot("11-butce-ekle")
                app.buttons["Vazgeç"].firstMatch.tap()
            }
        }

        tapTab("Özet")
        let card = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Kredi kartı")).firstMatch
        if !card.isHittable { app.swipeUp() }
        if card.waitForExistence(timeout: 3) {
            card.tap()
            Thread.sleep(forTimeInterval: 1)
            try shot("13-kart")
            app.navigationBars.buttons.firstMatch.tap()
            app.swipeDown()
            app.swipeDown()
        }
        app.buttons["Ayarlar"].firstMatch.tap()
        if app.buttons["Hesaplar"].firstMatch.waitForExistence(timeout: 3) {
            try shot("15-ayarlar")
            let backup = app.buttons["Dışa aktar ve yedekle"].firstMatch
            if !backup.isHittable { app.swipeUp() }
            if backup.waitForExistence(timeout: 2) {
                backup.tap()
                try shot("16-disa-aktar")
                app.navigationBars.buttons.firstMatch.tap()
                app.swipeDown()
            }
        }
        let accounts = app.buttons["Hesaplar"].firstMatch
        if accounts.waitForExistence(timeout: 3) {
            accounts.tap()
            try shot("8-hesaplar")
        }
    }
}
