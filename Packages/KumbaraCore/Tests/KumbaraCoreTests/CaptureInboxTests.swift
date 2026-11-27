import Foundation
import Testing
@testable import KumbaraCore

@Suite("Paylaş gelen kutusu (REQ-C2)")
struct CaptureInboxTests {
    let inbox = CaptureInbox(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("inbox-test-\(UUID().uuidString)", isDirectory: true))
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])

    @Test("Yazılan dosya sırayla geri okunur, silinir")
    func roundTrip() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let second = try inbox.deposit(jpeg, fileExtension: "JPG", now: t.addingTimeInterval(5))
        let first = try inbox.deposit(Data("%PDF-1.7".utf8), fileExtension: "pdf", now: t)
        #expect(inbox.pending() == [first, second])
        #expect(first.fileExtension == "pdf" && second.fileExtension == "jpg")
        #expect(try Data(contentsOf: second.url) == jpeg)

        inbox.remove(first)
        #expect(inbox.pending() == [second])
    }

    @Test("Geçersiz paylaşımlar reddedilir")
    func rejects() {
        #expect(throws: CaptureInbox.DepositError.unsupported) { try inbox.deposit(jpeg, fileExtension: "zip") }
        #expect(throws: CaptureInbox.DepositError.empty) { try inbox.deposit(Data(), fileExtension: "png") }
        #expect(throws: CaptureInbox.DepositError.tooLarge) {
            try inbox.deposit(Data(count: CaptureInbox.maxBytes + 1), fileExtension: "png")
        }
        #expect(inbox.pending().isEmpty)
    }

    @Test("Yarım yazımlar görünmez; eskiyenler ve fazlalık temizlenir")
    func trims() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        let stale = inbox.directory.appendingPathComponent(".\(Int64(t.timeIntervalSince1970 * 1000) - 7_200_000)-x.partial")
        let fresh = inbox.directory.appendingPathComponent(".\(Int64(t.timeIntervalSince1970 * 1000))-y.partial")
        try jpeg.write(to: stale)
        try jpeg.write(to: fresh)
        #expect(inbox.pending().isEmpty)

        var items: [CaptureInbox.Item] = []
        for index in 0..<(CaptureInbox.maxItems + 2) {
            items.append(try inbox.deposit(jpeg, fileExtension: "png", now: t.addingTimeInterval(Double(index))))
        }
        #expect(inbox.pending() == Array(items.suffix(CaptureInbox.maxItems)))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }
}
