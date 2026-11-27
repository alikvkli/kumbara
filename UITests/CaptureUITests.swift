import XCTest

/// Uçtan uca yakalama (REQ-C1, C3): paketteki örnek fiş görüntüsü gerçek Vision OCR'ından ve
/// ayrıştırıcıdan geçer; onay ekranında doğru tutar ve satıcı önerilmelidir (AC-C3-1).
final class CaptureUITests: XCTestCase {
    @MainActor
    func testDemoReceiptIsRecognised() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-demo-capture", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()

        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 30), "Onay ekranı açılmadı (OCR başarısız olabilir)")
        XCTAssertEqual(amount.value as? String, "1249,90")
        XCTAssertEqual(app.textFields["review.merchant"].value as? String, "Migros")

        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let suffix = ProcessInfo.processInfo.environment["SCREENSHOT_SUFFIX"] ?? "light"
            Thread.sleep(forTimeInterval: 1)
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("ios-9-fis-onay-\(suffix).png"))
        }
    }
}
