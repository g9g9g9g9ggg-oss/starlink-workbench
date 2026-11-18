import SwiftUI
import Combine

// MARK: - 聊天会话状态

@MainActor
final class ChatState: ObservableObject {
    let cid: String
    @Published var customer: WBCustomer
    @Published var detail: WBCustomerDetail?
    @Published var messages: [WBMessage] = []
    @Published var loading = true
    @Published var ipLocation = ""
    var since: Int64 = 0
    var rev: Int64 = 0

    init(customer: WBCustomer) {
        self.cid = customer.id
        self.customer = customer
    }
}

// MARK: - 工作台总状态（原生层唯一数据源）

@MainActor
final class WorkbenchStore: ObservableObject {

    let base: String
    weak var model: AppModel?

    @Published var me: WBMe?
    @Published var customers: [WBCustomer] = []
    @Published var customerFilter: String = "all"        // all / unread
    @Published var customerSearch = ""
    @Published var qrList: [WBQRCode] = []
    @Published var qrStats: WBQRStats?
    @Published var qrFetchedAt = Date()
    @Published var chat: ChatState?
    @Published var refreshError = ""

    let realtime = RealtimeCenter()
    private var customerTimer: Timer?
    private var qrTimer: Timer?
    private var lastEventAt = Date.distantPast
    private var lastSeenMap: [String: Int64] = [:]       // 轮询 diff 兜底提醒
    private var debounceTask: Task<Void, Never>?

    init(base: String, model: AppModel) {
        self.base = base
        self.model = model

        realtime.onEvent = { [weak self] event in
            self?.handleEvent(event)
        }
    }

    // MARK: 启停

    func start() {
        realtime.start(base: base)
        Task { await reloadMe() }
        Task { await refreshCustomers(silent: true) }
        Task { await refreshQR(silent: true) }
        // 轮询兜底（网页：列表 5s / 未读 8s / 码池 30s）
        customerTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshCustomers(silent: true) }
        }
        qrTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshQR(silent: true) }
        }
    }

    func stop() {
        realtime.stop()
        customerTimer?.invalidate()
        customerTimer = nil
        qrTimer?.invalidate()
        qrTimer = nil
    }

    func refreshAll() {
        Task { await reloadMe() }
        Task { await refreshCustomers(silent: true) }
        Task { await refreshQR(silent: true) }
        if let chat { Task { await refreshChat(state: chat) } }
    }

    func reloadMe() async {
        if let m = try? await WBAPI.me(base: base) {
            me = m
            model?.accountName = m.name
        }
    }

    var totalUnreadCount: Int {
        customers.filter { $0.unread > 0 }.count
    }

    // MARK: 提醒设置（与网页 alert.ts 同键）

    private var soundEnabled: Bool { UserDefaults.standard.object(forKey: "xl_sound") as? Bool ?? true }
    private var vibrateEnabled: Bool { UserDefaults.standard.object(forKey: "xl_vibrate") as? Bool ?? true }
    private var flashEnabled: Bool { UserDefaults.standard.bool(forKey: "xl_flash") }

    private func soundFor(_ key: String, _ fallback: SoundEngine.Kind) -> SoundEngine.Kind {
        let raw = UserDefaults.standard.string(forKey: key) ?? fallback.rawValue
        let kind = SoundEngine.Kind(rawValue: raw) ?? fallback
        return kind
    }

    private func inDND() -> Bool {
        let dnd = UserDefaults.standard.dictionary(forKey: "xl_dnd") as? [String: Any] ?? [:]
        let on = dnd["on"] as? Bool ?? false
        guard on else { return false }
        let s = dnd["s"] as? Int ?? 23
        let e = dnd["e"] as? Int ?? 8
        let hour = Calendar.current.component(.hour, from: Date())
        if s <= e { return hour >= s && hour < e }
        return hour >= s || hour < e
    }

    private func alert(kind: SoundEngine.Kind, haptic: [Int]?, vibrateOn: Bool? = nil) {
        guard !inDND() else { return }
        if soundEnabled { SoundEngine.shared.play(kind) }
        if vibrateOn ?? vibrateEnabled, let haptic { HapticEngine.vibrate(haptic) }
        if flashEnabled { TorchBlinker.blink(2) }
    }

    // MARK: SSE 事件路由（对齐网页 UnifiedAppShell 消费逻辑）

    private func handleEvent(_ event: WBEvent) {
        lastEventAt = Date()
        switch event.t {
        case "msg":
            if event.sender == "customer" {
                scheduleCustomerRefresh()
                if event.kind.isEmpty {
                    alert(kind: soundFor("xl_snd_msg", .dingDong), haptic: Constants.vibrateMessage)
                    if chat?.cid != event.custId || chat == nil {
                        let name = event.name.isEmpty ? "客户" : event.name
                        model?.showBanner(.info("💬 \(name)：\(event.preview)"))
                    }
                }
            }
            if let chat, chat.cid == event.custId {
                Task { await refreshChat(state: chat) }   // 新消息/已读回执/撤回更新
            }
        case "cust":
            scheduleCustomerRefresh()
            if event.kind == "doorbell" {
                model?.showDoorbellBanner(name: event.name, customerId: event.custId)
            } else if event.kind == "online" {
                alert(kind: soundFor("xl_snd_online", .off), haptic: Constants.vibrateOnline)
            } else if event.kind == "new" {
                alert(kind: soundFor("xl_snd_scan", .off), haptic: [160])
            }
        case "qr":
            Task { await refreshQR(silent: true) }
        default:
            break
        }
    }

    private func scheduleCustomerRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.refreshCustomers(silent: true)
        }
    }

    // MARK: 客户列表

    func refreshCustomers(silent: Bool) async {
        do {
            let list = try await WBAPI.customers(base: base,
                                                 search: customerSearch,
                                                 filter: customerFilter)
            pollDiffAlert(newList: list)
            customers = list
            refreshError = ""
        } catch let e as WBApiError {
            if !silent { refreshError = e.message }
        } catch {
            if !silent { refreshError = "网络异常" }
        }
    }

    /// SSE 断线期的轮询 diff 兜底（lastMessageAt 前移且最后发送者为客户 → 提醒）
    private func pollDiffAlert(newList: [WBCustomer]) {
        let fresh = Date().timeIntervalSince(lastEventAt) < 15
        for c in newList {
            if let old = lastSeenMap[c.id], c.lastMessageAt > old, c.lastSender == "customer" {
                if !fresh && (chat?.cid != c.id) {
                    alert(kind: soundFor("xl_snd_msg", .dingDong), haptic: Constants.vibrateMessage)
                    model?.showBanner(.info("💬 \(c.displayName)：\(c.lastPreview)"))
                }
            }
        }
        lastSeenMap = Dictionary(uniqueKeysWithValues: newList.map { ($0.id, $0.lastMessageAt) })
    }

    // MARK: 聊天

    func openChat(_ customer: WBCustomer) -> ChatState {
        if let existing = chat, existing.cid == customer.id {
            return existing
        }
        let state = ChatState(customer: customer)
        chat = state
        Task {
            await loadChat(state: state)
            await loadChatDetail(state: state)
        }
        return state
    }

    func openChatById(_ cid: String) {
        if chat?.cid == cid { return }
        if let c = customers.first(where: { $0.id == cid }) {
            _ = openChat(c)
        } else {
            let state = ChatState(customer: WBCustomer(["id": cid, "displayName": "客户"]))
            chat = state
            Task {
                await loadChat(state: state)
                await loadChatDetail(state: state)
            }
        }
    }

    func closeChat() {
        chat = nil
    }

    private func loadChat(state: ChatState) async {
        state.loading = true
        do {
            let page = try await WBAPI.messages(base: base, cid: state.cid, since: 0, rev: 0)
            let alive = page.messages.filter { $0.status != "deleted" }
            state.messages = alive
            state.since = alive.last.map { Int64($0.id) ?? 0 } ?? 0
            state.rev = alive.map(\.updatedAt).max() ?? 0
            state.customer.unread = page.customerUnread
            if page.customerUnread > 0 {
                await WBAPI.markRead(base: base, cid: state.cid)
                state.customer.unread = 0
                syncUnread(cid: state.cid)
            }
        } catch let e as WBApiError {
            model?.showToast(e.message)
        } catch {
            model?.showToast("消息加载失败")
        }
        state.loading = false
    }

    private func loadChatDetail(state: ChatState) async {
        if let d = try? await WBAPI.customerDetail(base: base, cid: state.cid) {
            state.detail = d
            state.customer.displayName = d.displayName
            if !d.ip.isEmpty {
                state.ipLocation = await WBAPI.ipLocation(base: base, ip: d.ip)
            }
        }
    }

    func refreshChat(state: ChatState) async {
        do {
            let page = try await WBAPI.messages(base: base, cid: state.cid, since: state.since, rev: state.rev)
            mergeMessages(state: state, incoming: page.messages)
            if page.customerUnread > 0 && state.cid == chat?.cid {
                await WBAPI.markRead(base: base, cid: state.cid)
                state.customer.unread = 0
                syncUnread(cid: state.cid)
            }
        } catch {
            // 静默（下轮 SSE/轮询再试）
        }
    }

    /// since/rev 增量合并：按 id 覆盖去重，剔除 deleted，按 id 升序
    private func mergeMessages(state: ChatState, incoming: [WBMessage]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: state.messages.filter { !$0.pending }.map { ($0.id, $0) })
        for m in incoming where m.status != "deleted" {
            byID[m.id] = m
        }
        let merged = byID.values.sorted { (Int64($0.id) ?? 0) < (Int64($1.id) ?? 0) }
        state.messages = merged
        if let lastID = merged.last.map({ Int64($0.id) ?? 0 }), lastID > state.since { state.since = lastID }
        let maxRev = incoming.map(\.updatedAt).max() ?? 0
        if maxRev > state.rev { state.rev = maxRev }
        syncUnread(cid: state.cid)
    }

    private func syncUnread(cid: String) {
        if let idx = customers.firstIndex(where: { $0.id == cid }) {
            customers[idx].unread = chat?.cid == cid ? (chat?.customer.unread ?? customers[idx].unread) : customers[idx].unread
        }
    }

    // MARK: 发送（乐观队列，对齐网页 pending 行语义）

    func sendText(_ text: String, quote: WBMessage?) {
        guard let chat, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let qName = quoteName(for: quote)
        let qText = quoteText(for: quote)
        let local = WBMessage(localID: "local-\(UUID().uuidString)", sender: "operator", type: "text",
                              content: text, fileUrl: "", quoteName: qName, quoteText: qText)
        chat.messages.append(local)
        Task {
            do {
                let sent = try await WBAPI.sendText(base: base, cid: chat.cid, content: text,
                                                    quoteName: qName, quoteText: qText)
                replacePending(state: chat, localID: local.id, with: sent)
                if Int64(sent.id) ?? 0 > chat.since { chat.since = Int64(sent.id) ?? 0 }
                if sent.updatedAt > chat.rev { chat.rev = sent.updatedAt }
            } catch let e as WBApiError {
                markFailed(state: chat, localID: local.id, message: e.message)
            } catch {
                markFailed(state: chat, localID: local.id, message: "发送失败")
            }
        }
    }

    func sendImage(fileId: String, quote: WBMessage?) {
        guard let chat else { return }
        let qName = quoteName(for: quote)
        let qText = quoteText(for: quote)
        let local = WBMessage(localID: "local-\(UUID().uuidString)", sender: "operator", type: "image",
                              content: "", fileUrl: "/files/\(fileId)", quoteName: qName, quoteText: qText)
        chat.messages.append(local)
        Task {
            do {
                let sent = try await WBAPI.sendImage(base: base, cid: chat.cid, fileId: fileId,
                                                     quoteName: qName, quoteText: qText)
                replacePending(state: chat, localID: local.id, with: sent)
                if Int64(sent.id) ?? 0 > chat.since { chat.since = Int64(sent.id) ?? 0 }
                if sent.updatedAt > chat.rev { chat.rev = sent.updatedAt }
            } catch let e as WBApiError {
                markFailed(state: chat, localID: local.id, message: e.message)
            } catch {
                markFailed(state: chat, localID: local.id, message: "发送失败")
            }
        }
    }

    private func quoteName(for quote: WBMessage?) -> String {
        guard let quote else { return "" }
        return quote.isOperator ? "我" : (chat?.customer.displayName ?? "客户")
    }

    private func quoteText(for quote: WBMessage?) -> String {
        guard let quote else { return "" }
        return quote.isImage ? "[图片]" : quote.content
    }

    private func replacePending(state: ChatState, localID: String, with sent: WBMessage) {
        if let idx = state.messages.firstIndex(where: { $0.id == localID }) {
            state.messages[idx] = sent
        }
    }

    private func markFailed(state: ChatState, localID: String, message: String) {
        if let idx = state.messages.firstIndex(where: { $0.id == localID }) {
            state.messages[idx].failed = true
            state.messages[idx].pending = false
        }
        model?.showToast(message)
    }

    func recall(_ message: WBMessage) {
        guard let chat else { return }
        Task {
            do {
                let updated = try await WBAPI.recallMessage(base: base, cid: chat.cid, mid: message.id)
                if let idx = chat.messages.firstIndex(where: { $0.id == updated.id }) {
                    chat.messages[idx].status = updated.status
                }
            } catch let e as WBApiError {
                model?.showToast(e.message)
            } catch {
                model?.showToast("撤回失败")
            }
        }
    }

    func deleteMessage(_ message: WBMessage) {
        guard let chat else { return }
        Task {
            do {
                try await WBAPI.deleteMessage(base: base, cid: chat.cid, mid: message.id)
                chat.messages.removeAll { $0.id == message.id }
            } catch let e as WBApiError {
                model?.showToast(e.message)
            } catch {
                model?.showToast("删除失败")
            }
        }
    }

    func retryPending(_ message: WBMessage) {
        guard let chat else { return }
        Task {
            do {
                let sent: WBMessage
                if message.isImage {
                    let fileId = message.fileUrl.replacingOccurrences(of: "/files/", with: "")
                    sent = try await WBAPI.sendImage(base: base, cid: chat.cid, fileId: fileId,
                                                     quoteName: message.quoteName, quoteText: message.quoteText)
                } else {
                    sent = try await WBAPI.sendText(base: base, cid: chat.cid, content: message.content,
                                                    quoteName: message.quoteName, quoteText: message.quoteText)
                }
                replacePending(state: chat, localID: message.id, with: sent)
            } catch {
                model?.showToast("重试失败")
            }
        }
    }

    func removePending(_ message: WBMessage) {
        chat?.messages.removeAll { $0.id == message.id }
    }

    // MARK: 码池

    func refreshQR(silent: Bool) async {
        do {
            async let list = WBAPI.qrcodes(base: base, search: "", status: "all")
            async let stats = WBAPI.qrStats(base: base)
            qrList = try await list
            qrStats = try await stats
            qrFetchedAt = Date()
        } catch let e as WBApiError {
            if !silent { model?.showToast(e.message) }
        } catch {
            if !silent { model?.showToast("码池加载失败") }
        }
    }

    func qrAction(_ action: String, id: String, confirmToast: String) {
        Task {
            do {
                let updated = try await WBAPI.qrAction(base: base, id: id, action: action)
                if let idx = qrList.firstIndex(where: { $0.id == id }) {
                    qrList[idx] = updated
                }
                await refreshQR(silent: true)
                model?.showToast(confirmToast)
            } catch let e as WBApiError {
                model?.showToast(e.message)
            } catch {
                model?.showToast("操作失败")
            }
        }
    }

    func qrDelete(id: String) {
        Task {
            do {
                try await WBAPI.qrDelete(base: base, id: id)
                qrList.removeAll { $0.id == id }
                await refreshQR(silent: true)
                model?.showToast("已删除")
            } catch let e as WBApiError {
                model?.showToast(e.message)
            } catch {
                model?.showToast("删除失败")
            }
        }
    }
}
