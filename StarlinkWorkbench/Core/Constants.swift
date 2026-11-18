import Foundation

/// 全局常量：域名入口、存储键、节奏参数
enum Constants {
    /// 服务器入口域名（与桌面版一致的容灾顺序；安卓内置主域）
    static let hosts: [String] = [
        "https://258766.lol",
        "https://9888.258766.lol",
        "https://988888.258766.lol",
    ]
    /// 工作台域名的公共后缀（用于外链判定：非本域 → 系统浏览器打开）
    static let workbenchHostSuffix = "258766.lol"

    /// BGAppRefresh 任务 ID（Info.plist BGTaskSchedulerPermittedIdentifiers 对应）
    static let bgTaskID = "com.starlink.workbench.doorbell"

    /// Keychain 记住密码
    static let keychainService = "com.starlink.workbench"
    static let keychainAccount = "remembered"

    /// UserDefaults 键
    static let rememberedUsernameKey = "xl_remembered_username"
    static let keepAliveKey = "xl_keepalive_enabled"
    static let hideFloatingButtonKey = "xl_hide_floating_settings"
    static let doorbellLastTsKey = "xl_doorbell_last_ts"
    static let doorbellHitCountKey = "xl_doorbell_hit_count"

    /// 节奏参数（对齐安卓壳）
    static let doorbellPollSeconds: TimeInterval = 3      // 后台守护 3 秒轮询
    static let probeTimeout: TimeInterval = 4             // 域名探测超时
    static let autoRetrySeconds: TimeInterval = 10        // 全部域名不可达时自动重试
    static let bannerAutoDismissSeconds: TimeInterval = 3

    /// 震动节奏（与网页版 alert.ts 完全一致，单位毫秒）
    static let vibrateMessage: [Int] = [350, 200, 350]
    static let vibrateOnline: [Int] = [160]
    static let vibrateDoorbell: [Int] = [420, 180, 420, 180, 420]
}

extension Notification.Name {
    /// 通知点击「立即接待」→ 前台路由到接待页
    static let openReception = Notification.Name("starlink.openReception")
    /// 收到新消息（后台通知触发）
    static let openMessage = Notification.Name("starlink.openMessage")
}
