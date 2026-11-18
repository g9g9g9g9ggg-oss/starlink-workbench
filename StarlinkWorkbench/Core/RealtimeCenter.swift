import Foundation

// MARK: - SSE 事件（/api/events，无 event: 字段，仅 data: JSON）

struct WBEvent {
    let t: String                   // hello/tick/msg/cust/qr/admin
    let wbId: String
    let custId: String
    let kind: String                // msg 缺省/'update'/'read'；cust 'new'/'online'/'doorbell'
    let sender: String              // customer/operator
    let name: String
    let preview: String
    let serverNow: Int64

    init?(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        t = obj.sOrEmpty("t")
        wbId = obj.sOrEmpty("wbId")
        custId = obj.sOrEmpty("custId")
        kind = obj.sOrEmpty("kind")
        sender = obj.sOrEmpty("sender")
        name = obj.sOrEmpty("name")
        preview = obj.sOrEmpty("preview")
        serverNow = obj.i("serverNow") ?? 0
    }
}

/// 实时中心：原生 SSE 长连接（对齐网页 lib/realtime.ts：断线 3 秒重建、tick 心跳、serverNow 校准）
@MainActor
final class RealtimeCenter: ObservableObject {

    enum State: Equatable {
        case idle, connecting, connected, reconnecting, stopped
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var serverOffsetMs: Int64 = 0   // serverNow - 本地时钟

    var onEvent: ((WBEvent) -> Void)?
    private var base: String = ""
    private var task: Task<Void, Never>?
    private var generation = 0

    func start(base: String) {
        self.base = base
        stop()
        generation += 1
        state = .connecting
        run(generation: generation)
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        state = .stopped
    }

    private func run(generation gen: Int) {
        task = Task { [weak self] in
            await self?.streamLoop(gen: gen)
        }
    }

    /// 断线重连（网页版：onerror 且 readyState===2 时 3 秒后重建）
    func reconnectSoon() {
        guard state != .stopped, state != .idle else { return }
        state = .reconnecting
        let gen = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.state = .connecting
            self.run(generation: gen)
        }
    }

    private func streamLoop(gen: Int) async {
        guard let url = WBAPI.makeURL(base: base, path: "api/events") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10_000_000        // SSE 长连接（无读超时语义）
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse else { throw WBApiError(status: 0, code: "", message: "网络异常") }
            guard http.statusCode == 200 else {
                // 401 = 会话失效，不再重连（登录态由上层处理）
                state = .stopped
                return
            }
            state = .connected
            var buffer = ""
            for try await line in bytes.lines {
                if Task.isCancelled || gen != generation { return }
                if line.hasPrefix("data:") {
                    buffer = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let event = WBEvent(buffer) { handle(event) }
                } else if line.hasPrefix("retry:") {
                    continue
                }
            }
            // 服务端关闭流 → 重连
            if !Task.isCancelled && gen == generation { reconnectSoon() }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled && gen == generation { reconnectSoon() }
        }
    }

    private func handle(_ event: WBEvent) {
        if event.serverNow > 0 {
            serverOffsetMs = event.serverNow - Int64(Date().timeIntervalSince1970 * 1000)
        }
        onEvent?(event)
    }

    /// 服务端时钟基准的当前毫秒
    var serverNowMs: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000) + serverOffsetMs
    }
}
