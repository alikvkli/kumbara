#if os(iOS)
import BackgroundTasks
import Foundation

/// Arka planda fiyat yenileme (REQ-M2): iOS fırsat buldukça çalıştırır; sıklığı sistem belirler.
/// Her çalışmada fiyat alarmları da değerlendirilir (REQ-M4).
enum BackgroundRefresh {
    static let identifier = "com.alikvkli.kumbara.refresh"

    /// Uygulama arka plana geçerken bir sonraki fırsatı ister (en erken 30 dk sonra).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif
