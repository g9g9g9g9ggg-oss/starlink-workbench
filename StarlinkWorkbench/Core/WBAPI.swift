import Foundation

// MARK: - 字典取值助手（服务端 JSON 手工解析，字段名与 routes/*.js 一字不差）

extension Dictionary where Key == String, Value == Any {
    func s(_ key: String) -> String? {
        if let v = self[key] as? String { return v }
        if let n = self[key] as? NSNumber { return n.stringValue }
        return nil
    }
    func sOrEmpty(_ key: String) -> String { s(key) ?? "" }
    func i(_ key: String) -> Int64? {
        if let n = self[key] as? NSNumber { return n.int64Value }
        if let v = self[key] as? String, let n = Int64(v) { return n }
        return nil
    }
    func b(_ key: String) -> Bool? {
        if let v = self[key] as? Bool { return v }
        if let n = self[key] as? NSNumber { return n.boolValue }
        return nil
    }
    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func arr(_ key: String) -> [[String: Any]] { (self[key] as? [[Any]])?.compactMap { $0 as? [String: Any] }
        ?? (self[key] as? [[String: Any]]) ?? [] }
    func strArr(_ key: String) -> [String] { (self[key] as? [Any])?.compactMap { $0 as? String } ?? [] }
}

// MARK: - 错误

struct WBApiError: Error {
    let status: Int
    let code: String
    let message: String
}

// MARK: - Identifiable（SwiftUI ForEach / sheet(item:) 用）

extension WBCustomer: Identifiable {}
extension WBMessage: Identifiable {}
extension WBQRCode: Identifiable {}

// MARK: - 数据模型（字段名 = 服务端 serialize 输出）

struct WBMe {
    let name: String
    let username: String
    let avatarUrl: String?          // '/files/<id>' 或 null
    let expiresAt: Int64?           // 毫秒
    let expired: Bool
    let mustChangePassword: Bool
    let announcement: String

    init(_ d: [String: Any]) {
        name = d.sOrEmpty("name")
        username = d.sOrEmpty("username")
        avatarUrl = d.s("avatarUrl")
        expiresAt = d.i("expiresAt")
        expired = d.b("expired") ?? false
        mustChangePassword = d.b("mustChangePassword") ?? false
        announcement = d.sOrEmpty("announcement")
    }
}

struct WBCustomer {
    let id: String
    var displayName: String
    var region: String
    var amount: String
    var tags: [String]
    var followStatus: String        // new/following/negotiated/paid/closed
    var note: String
    var specialNote1: String
    var specialNote2: String
    var unread: Int
    var qrName: String              // 空串 = 直接进入
    var qrDeleted: Bool
    var lastPreview: String
    var lastSender: String          // operator/customer
    var lastMessageAt: Int64        // 毫秒，0=无
    var createdAt: Int64
    var online: Bool
    var lastSeenAt: Int64

    init(_ d: [String: Any]) {
        id = d.sOrEmpty("id")
        displayName = d.sOrEmpty("displayName")
        region = d.sOrEmpty("region")
        amount = d.sOrEmpty("amount")
        tags = d.strArr("tags")
        followStatus = d.sOrEmpty("followStatus")
        note = d.sOrEmpty("note")
        specialNote1 = d.sOrEmpty("specialNote1")
        specialNote2 = d.sOrEmpty("specialNote2")
        unread = Int(d.i("unread") ?? 0)
        qrName = d.sOrEmpty("qrName")
        qrDeleted = d.b("qrDeleted") ?? false
        lastPreview = d.sOrEmpty("lastPreview")
        lastSender = d.sOrEmpty("lastSender")
        lastMessageAt = d.i("lastMessageAt") ?? 0
        createdAt = d.i("createdAt") ?? 0
        online = d.b("online") ?? false
        lastSeenAt = d.i("lastSeenAt") ?? 0
    }

    var followStatusLabel: String {
        switch followStatus {
        case "new": return "新客户"
        case "following": return "跟进中"
        case "negotiated": return "已谈成"
        case "paid": return "已付款"
        case "closed": return "已关闭"
        default: return followStatus
        }
    }
}

struct WBMessage {
    let id: String
    let sender: String              // operator/customer/system
    let type: String                // text/image
    let content: String             // 仅 text
    let fileUrl: String             // 仅 image，'/files/<id>'
    let quoteName: String
    let quoteText: String
    var status: String              // ok/read/recalled/deleted
    let updatedAt: Int64
    let createdAt: Int64
    var pending: Bool = false       // 本地乐观发送标记
    var failed: Bool = false

    init(_ d: [String: Any]) {
        id = d.sOrEmpty("id")
        sender = d.sOrEmpty("sender")
        type = d.sOrEmpty("type")
        content = d.sOrEmpty("content")
        fileUrl = d.sOrEmpty("fileUrl")
        quoteName = d.sOrEmpty("quoteName")
        quoteText = d.sOrEmpty("quoteText")
        status = d.sOrEmpty("status")
        updatedAt = d.i("updatedAt") ?? 0
        createdAt = d.i("createdAt") ?? 0
    }

    /// 乐观发送的本地占位
    init(localID: String, sender: String, type: String, content: String, fileUrl: String,
         quoteName: String, quoteText: String) {
        id = localID
        self.sender = sender
        self.type = type
        self.content = content
        self.fileUrl = fileUrl
        self.quoteName = quoteName
        self.quoteText = quoteText
        status = "ok"
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        createdAt = updatedAt
        pending = true
    }

    var isOperator: Bool { sender == "operator" }
    var isImage: Bool { type == "image" }
}

struct WBCustomerDetail {
    let id: String
    let displayName: String
    let entryCode: String
    let device: String
    let ip: String
    let qrName: String
    let qrStatus: String            // '' = 无码
    let messageCount: Int
    let createdAt: Int64
    let lastMessageAt: Int64
    var base: WBCustomer

    init(_ d: [String: Any]) {
        id = d.sOrEmpty("id")
        displayName = d.sOrEmpty("displayName")
        entryCode = d.sOrEmpty("entryCode")
        device = d.sOrEmpty("device")
        ip = d.sOrEmpty("ip")
        let qr = d.dict("qr")
        qrName = qr?.sOrEmpty("name") ?? ""
        qrStatus = qr?.sOrEmpty("status") ?? ""
        messageCount = Int(d.i("messageCount") ?? 0)
        createdAt = d.i("createdAt") ?? 0
        lastMessageAt = d.i("lastMessageAt") ?? 0
        base = WBCustomer(d)
    }
}

struct WBQRCode {
    let id: String
    let name: String
    let note: String
    let entryCode: String
    let urlPath: String             // 旧码为空
    let state: String               // active/buffer/expired/paused/revoked/deleted
    let stateLabel: String
    let leftMs: Int64
    let welcomeOverride: String
    let themeStyle: String
    let themeKefu: Bool
    let themeFooter: String
    let logoUrl: String
    let customerCount: Int
    let createdAt: Int64
    let entryUrl: String

    init(_ d: [String: Any]) {
        id = d.sOrEmpty("id")
        name = d.sOrEmpty("name")
        note = d.sOrEmpty("note")
        entryCode = d.sOrEmpty("entryCode")
        urlPath = d.sOrEmpty("urlPath")
        state = d.sOrEmpty("state")
        stateLabel = d.sOrEmpty("stateLabel")
        leftMs = d.i("leftMs") ?? 0
        welcomeOverride = d.sOrEmpty("welcomeOverride")
        let theme = d.dict("theme") ?? [:]
        themeStyle = theme.sOrEmpty("style")
        themeKefu = theme.b("kefu") ?? false
        themeFooter = theme.sOrEmpty("footer")
        logoUrl = d.sOrEmpty("logoUrl")
        customerCount = Int(d.i("customerCount") ?? 0)
        createdAt = d.i("createdAt") ?? 0
        entryUrl = d.sOrEmpty("entryUrl")
    }

    var stateColorKind: StateKind {
        switch state {
        case "active": return .good
        case "buffer": return .warn
        case "paused", "revoked", "deleted": return .muted
        default: return .bad
        }
    }

    enum StateKind { case good, warn, bad, muted }
}

struct WBQRStats {
    let total, active, buffer, paused, expired, revoked, deleted, customerTotal: Int
    let poolLeft: Int?

    init(_ d: [String: Any]) {
        total = Int(d.i("total") ?? 0)
        active = Int(d.i("active") ?? 0)
        buffer = Int(d.i("buffer") ?? 0)
        paused = Int(d.i("paused") ?? 0)
        expired = Int(d.i("expired") ?? 0)
        revoked = Int(d.i("revoked") ?? 0)
        deleted = Int(d.i("deleted") ?? 0)
        customerTotal = Int(d.i("customerTotal") ?? 0)
        poolLeft = d.i("poolLeft").map(Int.init)
    }
}

struct WBQuickText {
    let id: String
    let category: String
    let title: String
    let content: String
    init(_ d: [String: Any]) {
        id = d.sOrEmpty("id"); category = d.sOrEmpty("category")
        title = d.sOrEmpty("title"); content = d.sOrEmpty("content")
    }
}

struct WBQuickImage {
    let id: String
    let category: String
    let name: String
    let fileId: String
    var url: String
    init(_ d: [String: Any]) {
        id = d.sOrEmpty("id"); category = d.sOrEmpty("category")
        name = d.sOrEmpty("name"); fileId = d.sOrEmpty("fileId")
        url = d.sOrEmpty("url")
    }
}

struct WBSettingsInfo {
    let name: String
    let username: String
    let avatarUrl: String
    let logoUrl: String
    let welcomeDefault: String
    let expiresAt: Int64
    let maxIps: Int
    let qrFooterText: String

    init(_ d: [String: Any]) {
        name = d.sOrEmpty("name")
        username = d.sOrEmpty("username")
        avatarUrl = d.sOrEmpty("avatarUrl")
        logoUrl = d.sOrEmpty("logoUrl")
        welcomeDefault = d.sOrEmpty("welcomeDefault")
        expiresAt = d.i("expiresAt") ?? 0
        maxIps = Int(d.i("maxIps") ?? 0)
        qrFooterText = d.sOrEmpty("qrFooterText")
    }
}

struct WBSession {
    let id: String
    let current: Bool
    let browser: String
    let os: String
    let device: String
    let ip: String
    let loginAt: Int64
    let lastSeenAt: Int64

    init(_ d: [String: Any]) {
        id = d.sOrEmpty("id")
        current = d.b("current") ?? false
        browser = d.sOrEmpty("browser")
        os = d.sOrEmpty("os")
        device = d.sOrEmpty("device")
        ip = d.sOrEmpty("ip")
        loginAt = d.i("loginAt") ?? 0
        lastSeenAt = d.i("lastSeenAt") ?? 0
    }
}

// MARK: - API 客户端（会话走 HTTPCookieStorage.shared，与登录同源）

enum WBAPI {

    static func makeURL(base: String, path: String, query: [URLQueryItem] = []) -> URL? {
        var comps = URLComponents(string: base.hasSuffix("/") ? base + path : base + "/" + path)
        if !query.isEmpty { comps?.queryItems = query }
        return comps?.url
    }

    /// 通用 JSON 调用：返回解析后的对象；≥400 抛 WBApiError
    static func jsonCall(base: String, path: String, method: String = "GET",
                         body: [String: Any]? = nil, query: [URLQueryItem] = []) async throws -> Any {
        guard let url = makeURL(base: base, path: path, query: query) else {
            throw WBApiError(status: 0, code: "URL", message: "地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw WBApiError(status: 0, code: "NET", message: "网络异常")
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
        if http.statusCode >= 400 {
            let err = (obj as? [String: Any]) ?? [:]
            throw WBApiError(status: http.statusCode, code: err.sOrEmpty("code"),
                             message: err.sOrEmpty("error").isEmpty ? "请求失败（\(http.statusCode)）" : err.sOrEmpty("error"))
        }
        return obj
    }

    /// 上传（multipart/form-data）：kind = chat / brand
    static func upload(base: String, fileData: Data, fileName: String, mime: String,
                       kind: String, extraFields: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = makeURL(base: base, path: "api/files/upload") else {
            throw WBApiError(status: 0, code: "URL", message: "地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        let boundary = "xl-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        addField("kind", kind)
        for (k, v) in extraFields { addField(k, v) }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw WBApiError(status: 0, code: "NET", message: "网络异常")
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if http.statusCode >= 400 {
            throw WBApiError(status: http.statusCode, code: obj.sOrEmpty("code"),
                             message: obj.sOrEmpty("error").isEmpty ? "上传失败" : obj.sOrEmpty("error"))
        }
        return obj
    }

    /// 品牌设置 PUT /api/settings（multipart：文本字段 + 可选 avatar/logo 文件）
    static func putSettings(base: String, fields: [String: String],
                            avatar: (Data, String, String)? = nil,
                            logo: (Data, String, String)? = nil,
                            removeAvatar: Bool = false, removeLogo: Bool = false) async throws {
        guard let url = makeURL(base: base, path: "api/settings") else {
            throw WBApiError(status: 0, code: "URL", message: "地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.timeoutInterval = 60
        let boundary = "xl-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        for (k, v) in fields where !v.isEmpty { addField(k, v) }
        if removeAvatar { addField("removeAvatar", "1") }
        if removeLogo { addField("removeLogo", "1") }
        func addFile(_ name: String, _ file: (Data, String, String)) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(file.1)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(file.2)\r\n\r\n".data(using: .utf8)!)
            body.append(file.0)
            body.append("\r\n".data(using: .utf8)!)
        }
        if let avatar { addFile("avatarFile", avatar) }
        if let logo { addFile("logoFile", logo) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw WBApiError(status: 0, code: "NET", message: "网络异常")
        }
        if http.statusCode >= 400 {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw WBApiError(status: http.statusCode, code: "", message: obj.sOrEmpty("error").isEmpty ? "保存失败" : obj.sOrEmpty("error"))
        }
    }

    // MARK: 接待（reception.routes.js）

    static func customers(base: String, search: String, filter: String) async throws -> [WBCustomer] {
        var q = [URLQueryItem(name: "filter", value: filter)]
        if !search.isEmpty { q.append(URLQueryItem(name: "search", value: search)) }
        let obj = try await jsonCall(base: base, path: "api/customers", query: q)
        return (obj as? [Any])?.compactMap { $0 as? [String: Any] }.map(WBCustomer.init) ?? []
    }

    static func customerDetail(base: String, cid: String) async throws -> WBCustomerDetail {
        let obj = try await jsonCall(base: base, path: "api/customers/\(cid)")
        guard let d = obj as? [String: Any] else {
            throw WBApiError(status: 0, code: "", message: "数据异常")
        }
        return WBCustomerDetail(d)
    }

    static func patchCustomer(base: String, cid: String, fields: [String: Any]) async throws {
        _ = try await jsonCall(base: base, path: "api/customers/\(cid)", method: "PATCH", body: fields)
    }

    static func markRead(base: String, cid: String) async {
        _ = try? await jsonCall(base: base, path: "api/customers/\(cid)/read", method: "POST")
    }

    static func deleteCustomer(base: String, cid: String) async throws {
        _ = try await jsonCall(base: base, path: "api/customers/\(cid)", method: "DELETE")
    }

    static func ipLocation(base: String, ip: String) async -> String {
        guard !ip.isEmpty,
              let obj = try? await jsonCall(base: base, path: "api/ip-location",
                                            query: [URLQueryItem(name: "ip", value: ip)]) as? [String: Any]
        else { return "" }
        return obj.sOrEmpty("location")
    }

    // MARK: 消息

    struct MessagePage {
        let customerUnread: Int
        let messages: [WBMessage]
    }

    static func messages(base: String, cid: String, since: Int64, rev: Int64) async throws -> MessagePage {
        var q = [URLQueryItem(name: "since", value: String(since))]
        if rev > 0 { q.append(URLQueryItem(name: "rev", value: String(rev))) }
        let obj = try await jsonCall(base: base, path: "api/customers/\(cid)/messages", query: q)
        guard let d = obj as? [String: Any] else {
            throw WBApiError(status: 0, code: "", message: "数据异常")
        }
        let cust = d.dict("customer")
        let msgs = d.arr("messages").map(WBMessage.init)
        return MessagePage(customerUnread: Int(cust?.i("unread") ?? 0), messages: msgs)
    }

    static func sendText(base: String, cid: String, content: String,
                         quoteName: String, quoteText: String) async throws -> WBMessage {
        var body: [String: Any] = ["type": "text", "content": content]
        if !quoteName.isEmpty { body["quoteName"] = quoteName }
        if !quoteText.isEmpty { body["quoteText"] = quoteText }
        let obj = try await jsonCall(base: base, path: "api/customers/\(cid)/messages", method: "POST", body: body)
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "发送失败") }
        return WBMessage(d)
    }

    static func sendImage(base: String, cid: String, fileId: String,
                          quoteName: String, quoteText: String) async throws -> WBMessage {
        var body: [String: Any] = ["type": "image", "content": fileId]
        if !quoteName.isEmpty { body["quoteName"] = quoteName }
        if !quoteText.isEmpty { body["quoteText"] = quoteText }
        let obj = try await jsonCall(base: base, path: "api/customers/\(cid)/messages", method: "POST", body: body)
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "发送失败") }
        return WBMessage(d)
    }

    static func recallMessage(base: String, cid: String, mid: String) async throws -> WBMessage {
        let obj = try await jsonCall(base: base, path: "api/customers/\(cid)/messages/\(mid)/recall", method: "POST", body: [:])
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "撤回失败") }
        return WBMessage(d)
    }

    static func deleteMessage(base: String, cid: String, mid: String) async throws {
        _ = try await jsonCall(base: base, path: "api/customers/\(cid)/messages/\(mid)", method: "DELETE")
    }

    // MARK: 快捷素材（quick.routes.js）

    static func quickCategories(base: String) async throws -> (texts: [String], images: [String]) {
        let obj = try await jsonCall(base: base, path: "api/quick/categories")
        guard let d = obj as? [String: Any] else { return ([], []) }
        return (d.strArr("texts"), d.strArr("images"))
    }

    static func quickTexts(base: String, search: String, category: String) async throws -> [WBQuickText] {
        var q: [URLQueryItem] = []
        if !search.isEmpty { q.append(URLQueryItem(name: "search", value: search)) }
        if !category.isEmpty { q.append(URLQueryItem(name: "category", value: category)) }
        let obj = try await jsonCall(base: base, path: "api/quick/texts", query: q)
        return (obj as? [Any])?.compactMap { $0 as? [String: Any] }.map(WBQuickText.init) ?? []
    }

    static func quickImages(base: String, search: String, category: String) async throws -> [WBQuickImage] {
        var q: [URLQueryItem] = []
        if !search.isEmpty { q.append(URLQueryItem(name: "search", value: search)) }
        if !category.isEmpty { q.append(URLQueryItem(name: "category", value: category)) }
        let obj = try await jsonCall(base: base, path: "api/quick/images", query: q)
        return (obj as? [Any])?.compactMap { $0 as? [String: Any] }.map(WBQuickImage.init) ?? []
    }

    // MARK: 码池（qr.routes.js）

    static func qrcodes(base: String, search: String, status: String) async throws -> [WBQRCode] {
        var q: [URLQueryItem] = []
        if !search.isEmpty { q.append(URLQueryItem(name: "search", value: search)) }
        if !status.isEmpty && status != "all" { q.append(URLQueryItem(name: "status", value: status)) }
        let obj = try await jsonCall(base: base, path: "api/qrcodes", query: q)
        return (obj as? [Any])?.compactMap { $0 as? [String: Any] }.map(WBQRCode.init) ?? []
    }

    static func qrStats(base: String) async throws -> WBQRStats {
        let obj = try await jsonCall(base: base, path: "api/qrcodes/stats")
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "数据异常") }
        return WBQRStats(d)
    }

    static func qrDraft(base: String) async throws -> (entryCode: String, urlPath: String) {
        let obj = try await jsonCall(base: base, path: "api/qrcodes/draft", method: "POST", body: [:])
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "取码失败") }
        return (d.sOrEmpty("entryCode"), d.sOrEmpty("urlPath"))
    }

    static func qrOrigin(base: String) async -> String {
        guard let obj = try? await jsonCall(base: base, path: "api/qrcodes/origin") as? [String: Any] else { return "" }
        return obj.sOrEmpty("origin")
    }

    static func qrCreate(base: String, name: String, note: String, welcomeOverride: String,
                         themeStyle: String, kefu: Bool, footer: String,
                         logoFileId: String?, entryCode: String, urlPath: String) async throws -> WBQRCode {
        var theme: [String: Any] = ["style": themeStyle, "kefu": kefu]
        if !footer.isEmpty { theme["footer"] = footer }
        var body: [String: Any] = ["name": name, "theme": theme, "entryCode": entryCode, "urlPath": urlPath]
        if !note.isEmpty { body["note"] = note }
        if !welcomeOverride.isEmpty { body["welcomeOverride"] = welcomeOverride }
        if let logoFileId, !logoFileId.isEmpty { body["logoFile"] = logoFileId }
        let obj = try await jsonCall(base: base, path: "api/qrcodes", method: "POST", body: body)
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "制码失败") }
        return WBQRCode(d)
    }

    static func qrAction(base: String, id: String, action: String) async throws -> WBQRCode {
        // action: pause / resume / revoke / replace
        let obj = try await jsonCall(base: base, path: "api/qrcodes/\(id)/\(action)", method: "POST", body: [:])
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "操作失败") }
        return WBQRCode(d)
    }

    static func qrUpdate(base: String, id: String, name: String, note: String, welcomeOverride: String,
                         themeStyle: String, kefu: Bool, footer: String, logoFileId: String?) async throws -> WBQRCode {
        var theme: [String: Any] = ["style": themeStyle, "kefu": kefu]
        if !footer.isEmpty { theme["footer"] = footer }
        var body: [String: Any] = ["name": name, "theme": theme]
        if !note.isEmpty { body["note"] = note }
        if !welcomeOverride.isEmpty { body["welcomeOverride"] = welcomeOverride }
        if let logoFileId, !logoFileId.isEmpty { body["logoFile"] = logoFileId }
        let obj = try await jsonCall(base: base, path: "api/qrcodes/\(id)", method: "PATCH", body: body)
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "保存失败") }
        return WBQRCode(d)
    }

    static func qrDelete(base: String, id: String) async throws {
        _ = try await jsonCall(base: base, path: "api/qrcodes/\(id)", method: "DELETE")
    }

    static func qrImageURL(base: String, id: String) -> URL? {
        makeURL(base: base, path: "api/qrcodes/\(id)/image.png")
    }

    static func qrPreviewURL(base: String, code: String, urlPath: String, style: String,
                             kefu: Bool, footer: String, logoFileId: String?) -> URL? {
        var q = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "p", value: urlPath),
            URLQueryItem(name: "s", value: style),
            URLQueryItem(name: "kefu", value: kefu ? "1" : "0"),
        ]
        if !footer.isEmpty { q.append(URLQueryItem(name: "footer", value: footer)) }
        if let logoFileId, !logoFileId.isEmpty { q.append(URLQueryItem(name: "logo", value: logoFileId)) }
        return makeURL(base: base, path: "api/qrcodes/preview.png", query: q)
    }

    // MARK: 设置 / 安全

    static func settings(base: String) async throws -> WBSettingsInfo {
        let obj = try await jsonCall(base: base, path: "api/settings")
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "数据异常") }
        return WBSettingsInfo(d)
    }

    static func securitySessions(base: String) async throws -> [WBSession] {
        let obj = try await jsonCall(base: base, path: "api/security/sessions")
        return (obj as? [Any])?.compactMap { $0 as? [String: Any] }.map(WBSession.init) ?? []
    }

    static func kickSession(base: String, sid: String) async throws {
        _ = try await jsonCall(base: base, path: "api/security/sessions/\(sid)/kick", method: "POST", body: [:])
    }

    static func kickByIP(base: String, ip: String) async throws {
        _ = try await jsonCall(base: base, path: "api/security/sessions/kick-ip", method: "POST", body: ["ip": ip])
    }

    static func kickOthers(base: String) async throws {
        _ = try await jsonCall(base: base, path: "api/security/sessions/kick-others", method: "POST", body: [:])
    }

    static func changePassword(base: String, oldPassword: String, newPassword: String) async throws {
        _ = try await jsonCall(base: base, path: "api/security/change-password", method: "POST",
                               body: ["oldPassword": oldPassword, "newPassword": newPassword])
    }

    static func me(base: String) async throws -> WBMe {
        let obj = try await jsonCall(base: base, path: "api/me")
        guard let d = obj as? [String: Any] else { throw WBApiError(status: 0, code: "", message: "数据异常") }
        return WBMe(d)
    }
}
