import Foundation

/// Canlı taramada (VisionKit DataScanner) kameradan gelen her karenin yazıları buraya verilir;
/// kullanıcıya çekmeden önce ne gördüğünü söyler (specs/04 §7, v1.x). Toplam ancak art arda
/// birkaç karede aynı okunursa "bulundu" sayılır: titreyen kamerada yanlış tutar parlamasın.
public struct LiveScanGuide: Sendable {
    public enum Status: Hashable, Sendable {
        /// Kadrajda yazı yok.
        case empty
        /// Yazı var ama fiş gibi görünmüyor ya da toplam satırı yok.
        case searching
        /// Toplam görüldü ama henüz sabit değil.
        case steadying(Decimal)
        /// Aynı toplam yeterince karede okundu; çekmek için hazır.
        case found(Decimal)
    }

    /// Kaç ardışık karede aynı tutar okunmalı.
    public var requiredFrames: Int
    public private(set) var status: Status = .empty
    private var candidate: Decimal?
    private var streak = 0
    private let parser: CaptureParser

    public init(requiredFrames: Int = 3, parser: CaptureParser = CaptureParser()) {
        self.requiredFrames = requiredFrames
        self.parser = parser
    }

    /// Bir karenin yazılarını işler, güncel durumu döndürür.
    @discardableResult
    public mutating func observe(_ lines: [TextLine]) -> Status {
        guard lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            reset(to: .empty)
            return status
        }
        let result = parser.parse(lines)
        // Yalnız fiş ya da bildirimde tek toplam aranır; hesap hareketi listesinde canlı rehberlik yok.
        guard result.kind != .bankList, let amount = result.drafts.first?.amount, !amount.isLowConfidence else {
            // Bir kare kaçırmak (el titremesi) sabit tutarı hemen silmesin: yalnız seri sıfırlanır.
            if case .found = status { return status }
            reset(to: .searching)
            return status
        }
        if amount.value == candidate {
            streak += 1
        } else {
            candidate = amount.value
            streak = 1
        }
        status = streak >= requiredFrames ? .found(amount.value) : .steadying(amount.value)
        return status
    }

    private mutating func reset(to status: Status) {
        self.status = status
        candidate = nil
        streak = 0
    }
}
