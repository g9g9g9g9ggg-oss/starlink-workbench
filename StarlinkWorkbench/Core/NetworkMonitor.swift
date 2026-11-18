import Network
import Foundation

/// 断网监测：对齐安卓壳 —— 断网提醒；恢复后自动重载工作台（免登录）
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true
    var onLost: (() -> Void)?
    var onRestored: (() -> Void)?

    private let monitor = NWPathMonitor()
    private var started = false
    private var firstCallback = true

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                if self.firstCallback {
                    self.firstCallback = false
                    self.isConnected = connected
                    return
                }
                let wasConnected = self.isConnected
                self.isConnected = connected
                if wasConnected && !connected {
                    self.onLost?()
                } else if !wasConnected && connected {
                    self.onRestored?()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "starlink.network.monitor"))
    }
}
