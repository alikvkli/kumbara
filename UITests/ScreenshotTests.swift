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
            // Kaydırınca küçülen sekme çubuğu: açılana kadar aşağı çek; alt sayfadaysak geri dön.
            for attempt in 0..<5 where !(tab.waitForExistence(timeout: 2) && tab.isHittable) {
                let back = app.navigationBars.buttons.firstMatch
                if attempt >= 2, back.exists, back.isHittable { back.tap() } else { app.swipeDown() }
            }
            tab.tap()
        }

        /// Öğe görünür ve dokunulabilir olana kadar yavaşça kaydırır. Liste satırları ekrana gelmeden
        /// oluşmadığından, öğe yoksa aşağı doğru aranır; varsa ekranın ortasına doğru getirilir (altta sekme
        /// çubuğu ve piyasa şeridi örter). Bulunamazsa `false`: o kare atlanır, test düşmez.
        var misses = 0
        func reveal(_ element: XCUIElement) -> Bool {
            let window = app.windows.firstMatch
            _ = element.waitForExistence(timeout: 1)
            for attempt in 0..<14 {
                let frame = window.frame
                if element.exists {
                    let box = element.frame
                    let visible = box.minY > frame.minY + 100 && box.maxY < frame.maxY - 220
                    if visible, element.isHittable { return true }
                }
                // İçeriği yukarı it (aşağıdakini getir); öğe yukarıda kaldıysa ya da aşağıda bulunamadıysa
                // yukarı doğru ara.
                let towardTop = (element.exists && element.frame.midY < frame.minY + 100) || attempt >= 7
                let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.35 : 0.65))
                let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.6 : 0.4))
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
                Thread.sleep(forTimeInterval: 0.4)
            }
            let found = element.exists && element.isHittable
            if !found {
                // Tanı için: bulunamayan öğenin anındaki ekran.
                misses += 1
                let data = XCUIScreen.main.screenshot().pngRepresentation
                try? data.write(to: output.appendingPathComponent("ios-miss-\(misses)-\(suffix).png"))
                print("reveal: bulunamadı → \(element.debugDescription.prefix(300))")
            }
            return found
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
        // Birikim planı (specs/10 §7)
        let planRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Her ayın")).firstMatch
        if reveal(planRow) {
            planRow.tap()
            Thread.sleep(forTimeInterval: 1)
            try shot("22-birikim-plani")
            app.navigationBars.buttons.firstMatch.tap()
        }
        let gram = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Gram altın")).firstMatch
        if reveal(gram) {
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
            // Ödeme takvimi (specs/10 §5)
            let paymentCalendar = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Ödeme takvimi")).firstMatch
            if reveal(paymentCalendar) {
                paymentCalendar.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("20-odeme-takvimi")
                app.navigationBars.buttons.firstMatch.tap()
            }
            // Abonelikler (specs/10 §2)
            let subscriptions = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Abonelikler")).firstMatch
            if reveal(subscriptions) {
                subscriptions.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("17-abonelikler")
                app.navigationBars.buttons.firstMatch.tap()
            }
            // Alabilir miyim? (specs/10 §3)
            let purchase = app.buttons["Alabilir miyim?"].firstMatch
            if reveal(purchase) {
                purchase.tap()
                let field = app.textFields["purchase.amount"]
                if field.waitForExistence(timeout: 3) {
                    field.tap()
                    app.typeText("12000")
                    try shot("21-alabilir-miyim")
                }
                app.buttons["Kapat"].firstMatch.tap()
            }
            // Kira artışı (specs/12)
            let rent = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Kira artışı")).firstMatch
            if reveal(rent) {
                rent.tap()
                let contract = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Ev kirası")).firstMatch
                if contract.waitForExistence(timeout: 3) {
                    contract.tap()
                    Thread.sleep(forTimeInterval: 1)
                    try shot("26-kira")
                    app.navigationBars.buttons.firstMatch.tap()
                }
                app.navigationBars.buttons.firstMatch.tap()
            }
            app.swipeDown()
            app.swipeDown()
        }

        tapTab("Özet")
        let card = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Kredi kartı")).firstMatch
        if reveal(card) {
            card.tap()
            Thread.sleep(forTimeInterval: 1)
            try shot("13-kart")
            // Asgari ödersen (specs/11)
            let interest = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Asgari ödersen")).firstMatch
            if reveal(interest) {
                interest.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("25-kart-faiz")
                app.navigationBars.buttons.firstMatch.tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
            app.swipeDown()
            app.swipeDown()
        }
        // Aylık rapor (specs/10 §1)
        let reports = app.buttons["Aylık raporlar"].firstMatch
        if reveal(reports) {
            reports.tap()
            let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
            let year = String(Calendar.current.component(.year, from: previousMonth))
            let latest = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", year)).firstMatch
            if latest.waitForExistence(timeout: 3) {
                latest.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("18-rapor")
                app.swipeUp()
                try shot("18b-rapor-birikim")
                let share = app.buttons["Paylaş"].firstMatch
                if share.waitForExistence(timeout: 2) {
                    share.tap()
                    if app.switches["Tutarları göster"].firstMatch.waitForExistence(timeout: 3) {
                        try shot("19-rapor-paylas")
                        app.buttons["Kapat"].firstMatch.tap()
                    }
                }
                app.navigationBars.buttons.firstMatch.tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
            app.swipeDown()
            app.swipeDown()
            app.swipeDown()
        }
        // Alacak ve borçlar (specs/10 §4)
        let debts = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Alacak ve borçlar")).firstMatch
        if reveal(debts) {
            debts.tap()
            Thread.sleep(forTimeInterval: 1)
            try shot("23-alacak-borc")
            let ayse = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Ayşe")).firstMatch
            if ayse.waitForExistence(timeout: 2) {
                ayse.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("24-kisi")
                app.navigationBars.buttons.firstMatch.tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
            app.swipeDown()
            app.swipeDown()
            app.swipeDown()
        }
        // Krediler (specs/13)
        let loans = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Krediler")).firstMatch
        if reveal(loans) {
            loans.tap()
            Thread.sleep(forTimeInterval: 1)
            try shot("27-krediler")
            let loan = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "İhtiyaç kredisi")).firstMatch
            if loan.waitForExistence(timeout: 2) {
                loan.tap()
                Thread.sleep(forTimeInterval: 1)
                try shot("28-kredi")
                app.navigationBars.buttons.firstMatch.tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
            app.swipeDown()
            app.swipeDown()
            app.swipeDown()
        }
        app.buttons["Ayarlar"].firstMatch.tap()
        if app.buttons["Hesaplar"].firstMatch.waitForExistence(timeout: 3) {
            try shot("15-ayarlar")
            let backup = app.buttons["Dışa aktar ve yedekle"].firstMatch
            if reveal(backup) {
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
