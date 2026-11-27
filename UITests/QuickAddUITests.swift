import XCTest

/// REQ-L4: Yeni işlem uygulama açıkken en fazla 2 dokunuşta kaydedilir ve tutar alanı
/// klavye açık şekilde odaklı gelir.
final class QuickAddUITests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()
        return app
    }

    @MainActor
    func testExpenseIsSavedInTwoTaps() throws {
        let app = launch()
        // Dokunuş 1: araç çubuğundaki "+"
        let add = app.buttons["Yeni işlem"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let amount = app.textFields["editor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: amount)
        waitForExpectations(timeout: 5)

        // Klavyeden yazmak dokunuş sayılmaz: alan zaten odakta.
        app.typeText("250")

        // Dokunuş 2: Kaydet
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        // Kayıt İşlemler listesinde görünür.
        app.tabBars.buttons["İşlemler"].tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "₺250,00"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSaveIsDisabledWithoutAmount() throws {
        let app = launch()
        app.buttons["Yeni işlem"].firstMatch.tap()
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
    }
}
