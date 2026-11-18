import Foundation
import BackgroundTasks
import AVFoundation

/// 后台门铃守护：对齐安卓 AlertService（前台服务 3s 轮询 /api/doorbell/last）+ WatchdogReceiver。
/// iOS 无前台服务，采用两级方案：
///   标准 = BGAppRefresh 系统调度（系统决定唤醒时机）
///   强   = 静音音频保活 + 3 秒轮询（侧载/企业场景可用，消耗电量）
/// 前台时自动停用（网页版 SSE 实时提醒接管，避免重复响铃，与安卓 AppInForeground 逻辑一致）。
@MainActor
final class DoorbellGuard: ObservableObject {

    nonisolated(unsafe) static var active: DoorbellGuard?

    @Published private(set) var lastPoll: Date?
    @Published private(set) var hitCount: Int = UserDefaults.standard.integer(forKey: Constants.doorbellHitCountKey)
    @Published private(set) var bridged = false      // 会话桥接：API 侧能否读到登录态
    @Published private(set) var guardActive = false

    var baseURL: URL?

    private var source: DispatchSourceTimer?
    private var keepAlivePlayer: AVAudioPlayer?
    private var lastNotifiedTs: Double = UserDefaults.standard.double(forKey: Constants.doorbellLastTsKey)
    private let pollQueue = DispatchQueue(label: "starlink.doorbell.poll")

    // MARK: BGTask 注册（App 启动前调用一次）

    nonisolated static func registerBgTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Constants.bgTaskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            DispatchQueue.main.async {
                Task { @MainActor in
                    DoorbellGuard.active?.handleBgTask(refresh)
                }
            }
        }
    }

    // MARK: 模式切换

    func enterBackground(baseURL: URL?, keepAlive: Bool) {
        guardActive = true
        self.baseURL = baseURL
        scheduleBgRefresh()
        if keepAlive {
            keepAlivePlayer = SoundEngine.shared.startKeepAlive()
            startPolling()
        }
    }

    func stopBackgroundMode() {
        guardActive = false
        source?.cancel()
        source = nil
        if keepAlivePlayer != nil {
            keepAlivePlayer?.stop()
            keepAlivePlayer = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    // MARK: 轮询

    private func startPolling() {
        source?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + 1, repeating: Constants.doorbellPollSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.poll() }
        }
        timer.resume()
        source = timer
    }

    func poll() async {
        guard let base = baseURL?.absoluteString else { return }
        let result = await APIClient.doorbellLast(base: base)
        applyPollResult(result)
    }

    private func applyPollResult(_ result: APIClient.DoorbellLast?) {
        lastPoll = Date()
        guard let result else {
            // 401/网络异常：API 侧未桥接会话（网页登录模式下无法读取 httpOnly cookie）
            bridged = false
            return
        }
        bridged = true
        guard result.ts > 0, result.ts > lastNotifiedTs else { return }
        lastNotifiedTs = result.ts
        UserDefaults.standard.set(result.ts, forKey: Constants.doorbellLastTsKey)
        AlertCenter.shared.notifyDoorbell(name: result.name ?? "")
        hitCount += 1
        UserDefaults.standard.set(hitCount, forKey: Constants.doorbellHitCountKey)
    }

    // MARK: BGAppRefresh（标准守护）

    func scheduleBgRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Constants.bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func handleBgTask(_ task: BGAppRefreshTask) {
        scheduleBgRefresh()   // 先排下一次（看门狗语义）
        let work = Task {
            await self.poll()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
