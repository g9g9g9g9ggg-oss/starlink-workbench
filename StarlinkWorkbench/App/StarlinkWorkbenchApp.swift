import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct StarlinkWorkbenchApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // BGTask 必须在启动完成前注册（对齐安卓 WatchdogReceiver 看门狗）
        DoorbellGuard.registerBgTask()
        // 通知代理与分类（对齐安卓 AlertService 通知）
        AlertCenter.shared.configure()
        // 断网监测（对齐安卓断网提醒/恢复重载）
        NetworkMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { model.handleOpenURL($0) }
        }
        .onChange(of: scenePhase) { model.scenePhaseChanged($0) }
    }
}
