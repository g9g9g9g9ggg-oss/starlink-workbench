import SwiftUI
import Combine
import WebKit

// MARK: - 阶段与横幅

enum AppPhase: Equatable {
    case connecting      // 域名探测中
    case failed          // 全部域名不可达（自动重试 + 手动重连）
    case login           // 未登录
    case workbench       // 工作台运行中
}

enum ShellBanner: Equatable {
    case networkLost
    case networkRestored
    case doorbell(name: String)
    case info(String)

    var text: String {
        switch self {
        case .networkLost: return "⚠️ 网络连接断开"
        case .networkRestored: return "✅ 网络已恢复，正在重新加载工作台"
        case .doorbell(let name): return "🔔 客户「\(name)」正在门口等，点此接待"
        case .info(let t): return t
        }
    }
}

enum ProbeState: Equatable {
    case pending, probing, ok, fail
}

struct ProbeRow: Identifiable, Equatable {
    let id: Int
    let host: String
    var state: ProbeState
}

// MARK: - 全局模型

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: AppPhase = .connecting
    @Published var probeRows: [ProbeRow] = []
    @Published var baseURL: URL?
    @Published var accountName: String = UserDefaults.standard.string(forKey: Constants.rememberedUsernameKey) ?? ""
    @Published var banner: ShellBanner?
    @Published var toast: String?
    @Published var showSettings = false
    @Published var keepAliveMode: Bool {
        didSet { UserDefaults.standard.set(keepAliveMode, forKey: Constants.keepAliveKey) }
    }

    let doorbellGuard: DoorbellGuard
    private lazy var controller = WorkbenchController(model: self)
    private var bannerToken = UUID()
    private var toastToken = UUID()

    var webController: WorkbenchController { controller }

    /// 原生工作台状态层（登录成功后创建；网页兜底路径为 nil）
    @Published var store: WorkbenchStore?

    init() {
        keepAliveMode = UserDefaults.standard.bool(forKey: Constants.keepAliveKey)
        doorbellGuard = DoorbellGuard()
        DoorbellGuard.active = doorbellGuard
        probeRows = Constants.hosts.enumerated().map { ProbeRow(id: $0.offset, host: $0.element, state: .pending) }

        // 断网/恢复（对齐安卓：断网提醒、恢复自动重载免登录）
        NetworkMonitor.shared.onLost = { [weak self] in
            self?.showBanner(.networkLost)
        }
        NetworkMonitor.shared.onRestored = { [weak self] in
            guard let self else { return }
            if self.phase == .workbench {
                self.controller.reloadIfWorkbench()
                self.showBanner(.networkRestored)
            }
        }
        Task { await bootstrap() }
    }

    // MARK: 启动与域名探测

    func bootstrap() async {
        phase = .connecting
        for i in probeRows.indices { probeRows[i].state = .pending }
        let hostStrings = probeRows.map(\.host)
        guard let base = await ServerProber.probeAll(hostStrings, onRow: { [weak self] index, state in
            self?.probeRows[index].state = state
        }) else {
            phase = .failed
            scheduleAutoRetry()
            return
        }
        baseURL = URL(string: base)
        doorbellGuard.baseURL = baseURL
        let me = await APIClient.me(base: base)
        if let me {
            accountName = me.name
            phase = .workbench
            enterWorkbench(base: base, path: "/reception")
        } else {
            accountName = UserDefaults.standard.string(forKey: Constants.rememberedUsernameKey) ?? ""
            phase = .login
        }
    }

    private func scheduleAutoRetry() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Constants.autoRetrySeconds * 1_000_000_000))
            if let self, self.phase == .failed {
                await self.bootstrap()
            }
        }
    }

    func retryConnect() {
        Task { await bootstrap() }
    }

    // MARK: 登录（对齐安卓登录会话 + 记住密码）

    enum LoginState: Equatable {
        case idle, loading
        case error(String)
    }
    @Published var loginState: LoginState = .idle

    // 演示链路（无网回归用）：失败态 / 成功态
    func demoLoginFail() {
        loginState = .error("账号或密码错误")
    }

    func demoLoginOk() {
        showToast("登录成功 · 已进入接待页（演示）")
        if let base = baseURL {
            enterWorkbench(base: base.absoluteString, path: "/reception")
        } else {
            Task {
                let base = await ServerProber.probeAll(Constants.hosts, onRow: { _, _ in })
                if let base { enterWorkbench(base: base, path: "/reception") }
            }
        }
    }

    func login(username: String, password: String, remember: Bool) {
        guard !username.isEmpty, !password.isEmpty else {
            loginState = .error("请输入账号和密码")
            return
        }
        loginState = .loading
        Task {
            await performLogin(username: username, password: password, remember: remember)
        }
    }

    private func performLogin(username: String, password: String, remember: Bool) async {
        var base = baseURL?.absoluteString
        if base == nil {
            let hostStrings = Constants.hosts
            base = await ServerProber.probeAll(hostStrings, onRow: { [weak self] index, state in
                self?.probeRows[index].state = state
            })
        }
        guard let base else {
            loginState = .error("服务器不可达，请检查网络后重试")
            return
        }
        baseURL = URL(string: base)
        doorbellGuard.baseURL = baseURL

        let outcome = await APIClient.login(base: base, username: username, password: password)
        switch outcome {
        case .ok(let mustChangePassword):
            if remember {
                KeychainStore.save(password: password)
                UserDefaults.standard.set(username, forKey: Constants.rememberedUsernameKey)
            } else {
                KeychainStore.clear()
                UserDefaults.standard.removeObject(forKey: Constants.rememberedUsernameKey)
            }
            accountName = username
            loginState = .idle
            if mustChangePassword {
                // 首次登录强制改密：交给网页自己的改密流程（加载根路径走 SPA 引导）
                enterWorkbench(base: base, path: "/")
                showToast("首次登录请先修改初始密码")
            } else {
                enterWorkbench(base: base, path: "/reception")
            }
        case .needEmailCode(let message):
            loginState = .idle
            showToast("该账号开启了邮箱验证码，请稍候转入网页登录页完成验证")
            useWebLogin(after: message)
        case .failure(let message):
            loginState = .error(message)
        }
    }

    /// 管理员邮箱二次验证 / 网页登录兜底：直接进入网页登录页（工作台自渲染）
    func useWebLogin(after note: String? = nil) {
        guard let base = baseURL?.absoluteString else { return }
        accountName = ""
        phase = .workbench
        controller.load(base: base, path: "/")
        if let note { showToast(note) }
    }

    func enterWorkbench(base: String, path: String) {
        baseURL = URL(string: base)
        doorbellGuard.baseURL = baseURL
        phase = .workbench
        if path == "/reception" {
            // 原生工作台：状态层 + SSE + 轮询
            let s = WorkbenchStore(base: base, model: self)
            ImageBaseHolder.shared.base = base
            store = s
            s.start()
        } else {
            // 首改密引导等网页路径仍走壳
            store = nil
            controller.load(base: base, path: path)
        }
        requestNotificationAuthIfNeeded()
    }

    /// 首次进入工作台时请求通知权限（门铃/消息通知的前置）
    private func requestNotificationAuthIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "xl_notif_auth_asked") else { return }
        UserDefaults.standard.set(true, forKey: "xl_notif_auth_asked")
        Task {
            _ = await AlertCenter.shared.requestAuthorization()
        }
    }

    // MARK: 退出登录（吊销会话 + 清 Cookie/缓存/密码）

    func logout() async {
        if let base = baseURL?.absoluteString {
            await APIClient.logout(base: base)
        }
        store?.stop()
        store = nil
        APIClient.clearSessionCookies()
        controller.clearWebData()
        KeychainStore.clear()
        UserDefaults.standard.removeObject(forKey: Constants.rememberedUsernameKey)
        accountName = ""
        phase = .login
        showToast("已退出登录，本机会话与缓存已清除")
    }

    // MARK: 场景切换（后台守护调度，对齐安卓 AlertService/WatchdogReceiver）

    func scenePhaseChanged(_ scene: ScenePhase) {
        switch scene {
        case .active:
            doorbellGuard.stopBackgroundMode()
        case .background:
            doorbellGuard.enterBackground(baseURL: baseURL, keepAlive: keepAliveMode)
        default:
            break
        }
    }

    // MARK: 深链

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "starlink" else { return }
        if phase == .workbench {
            controller.goToReception()
        }
    }

    // MARK: 横幅与轻提示

    func showBanner(_ b: ShellBanner) {
        banner = b
        let token = UUID()
        bannerToken = token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Constants.bannerAutoDismissSeconds * 1_000_000_000))
            if let self, self.bannerToken == token { self.banner = nil }
        }
    }

    func showDoorbellBanner(name: String, customerId: String?) {
        showBanner(.doorbell(name: name))
        HapticEngine.vibrate(Constants.vibrateDoorbell)
        SoundEngine.shared.play(.doorbell)
        doorbellTargetId = customerId
    }

    /// 门铃横幅点击后的落地会话
    @Published var doorbellTargetId: String?

    func openDoorbellTarget() {
        guard let id = doorbellTargetId, let store else {
            webController.goToReception()
            return
        }
        store.openChatById(id)
    }

    func showToast(_ text: String) {
        toast = text
        let token = UUID()
        toastToken = token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if let self, self.toastToken == token { self.toast = nil }
        }
    }
}
