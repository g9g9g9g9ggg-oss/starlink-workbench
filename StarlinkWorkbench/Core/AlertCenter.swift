import Foundation
import UserNotifications

/// 本地通知中心：对齐安卓 AlertService 的三类事件通知 + 门铃「立即接待」快捷操作。
/// 仅在后台守护轮询发现事件时使用（前台提醒由网页版提醒中心承担，避免重复响铃）。
final class AlertCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()

    @Published var authorized = false

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let goReception = UNNotificationAction(identifier: "GO_RECEPTION",
                                               title: "立即接待",
                                               options: [.foreground])
        let doorbell = UNNotificationCategory(identifier: "DOORBELL",
                                              actions: [goReception],
                                              intentIdentifiers: [],
                                              options: [])
        let message = UNNotificationCategory(identifier: "MESSAGE",
                                             actions: [],
                                             intentIdentifiers: [],
                                             options: [])
        center.setNotificationCategories([doorbell, message])
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorized = settings.authorizationStatus == .authorized
            }
        }
    }

    @MainActor
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = granted
        return granted
    }

    // MARK: 事件通知

    func notifyDoorbell(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "前台门铃"
        content.body = name.isEmpty ? "客户正在门口等，点此接待" : "客户「\(name)」正在门口等，点此接待"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("doorbell.wav"))
        content.categoryIdentifier = "DOORBELL"
        add(identifier: "starlink.doorbell", content: content)
    }

    func notifyMessage(preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "收到新消息"
        content.body = preview.isEmpty ? "客户发来了新消息" : preview
        content.sound = UNNotificationSound(named: UNNotificationSoundName("default.wav"))
        content.categoryIdentifier = "MESSAGE"
        add(identifier: "starlink.message", content: content)
    }

    func notifyOnline(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "客户上线"
        content.body = name.isEmpty ? "有客户上线了" : "客户「\(name)」上线了"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("knock.wav"))
        add(identifier: "starlink.online", content: content)
    }

    private func add(identifier: String, content: UNNotificationContent) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// 前台也以横幅+声音呈现（iOS 14+ banner 样式）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }

    /// 点击路由：门铃/消息 → 打开接待页
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        if response.actionIdentifier == "GO_RECEPTION" || category == "DOORBELL" {
            NotificationCenter.default.post(name: .openReception, object: nil)
        } else if category == "MESSAGE" {
            NotificationCenter.default.post(name: .openMessage, object: nil)
        }
    }
}
