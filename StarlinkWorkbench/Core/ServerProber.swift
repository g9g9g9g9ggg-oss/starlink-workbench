import Foundation

/// 域名探活：对齐桌面/安卓壳逻辑 —— GET /api/me，任何 HTTP 响应（含 401）即视为可达。
enum ServerProber {

    /// 顺序探测；返回第一个可达域名（字符串形式），全部失败返回 nil。
    /// onRow 在主线程回调每个域名的探测状态（用于连接页逐行动画）。
    static func probeAll(_ hosts: [String],
                         onRow: @escaping (Int, ProbeState) -> Void) async -> String? {
        for (index, host) in hosts.enumerated() {
            await MainActor.run { onRow(index, .probing) }
            if await probe(host: host) {
                await MainActor.run { onRow(index, .ok) }
                return host
            }
            await MainActor.run { onRow(index, .fail) }
        }
        return nil
    }

    /// 单域名探活：任何 HTTP 状态都算可达；连接错误/超时 = 不可达
    static func probe(host: String) async -> Bool {
        guard let base = URL(string: host) else { return false }
        let url = base.appendingPathComponent("api/me")
        var req = URLRequest(url: url)
        req.timeoutInterval = Constants.probeTimeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
