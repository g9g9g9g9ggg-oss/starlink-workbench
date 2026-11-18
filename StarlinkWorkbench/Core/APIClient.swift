import Foundation

/// 工作台 API 客户端（会话 cookie 存 HTTPCookieStorage.shared，与 WKWebView 双向桥接）
enum APIClient {

    struct MeInfo {
        let role: String   // "workbench" / "admin"
        let name: String
    }

    enum LoginOutcome {
        case ok(mustChangePassword: Bool)   // 首次登录强制改密时须先走网页引导
        case needEmailCode(String)          // 管理员邮箱验证码流程，需转网页登录
        case failure(String)
    }

    private static func makeRequest(base: String, path: String, method: String = "GET") -> URLRequest? {
        guard let url = URL(string: base)?.appendingPathComponent(path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return req
    }

    // MARK: 登录态

    /// GET /api/me —— 已登录返回身份；401/未登录返回 nil
    static func me(base: String) async -> MeInfo? {
        guard let req = makeRequest(base: base, path: "api/me") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let obj else { return nil }
            let role = obj["role"] as? String ?? "workbench"
            let name = obj["name"] as? String ?? ""
            return MeInfo(role: role, name: name)
        } catch {
            return nil
        }
    }

    /// POST /api/login —— {username,password}；成功即会话 cookie 落入共享存储
    static func login(base: String, username: String, password: String) async -> LoginOutcome {
        guard let url = URL(string: base)?.appendingPathComponent("api/login") else {
            return .failure("域名无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["username": username, "password": password]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .failure("网络异常") }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            switch http.statusCode {
            case 200...299:
                return .ok(mustChangePassword: obj["mustChangePassword"] as? Bool == true)
            case 401:
                return .failure(obj["error"] as? String ?? "账号或密码错误")
            case 429:
                if obj["needEmailCode"] as? Bool == true {
                    return .needEmailCode(obj["error"] as? String ?? "需要邮箱验证码")
                }
                return .failure(obj["error"] as? String ?? "登录尝试过于频繁，请稍后再试")
            default:
                return .failure(obj["error"] as? String ?? "登录失败（\(http.statusCode)）")
            }
        } catch {
            return .failure("网络异常，请检查网络后重试")
        }
    }

    /// POST /api/logout —— 吊销服务端会话
    static func logout(base: String) async {
        guard let req = makeRequest(base: base, path: "api/logout", method: "POST") else { return }
        _ = try? await URLSession.shared.data(for: req)
    }

    /// GET /api/doorbell/last —— 后台守护轮询：{last:{ts,custId,name}|null}
    struct DoorbellLast {
        let ts: Double
        let customerId: String?
        let name: String?
    }
    static func doorbellLast(base: String) async -> DoorbellLast? {
        guard let req = makeRequest(base: base, path: "api/doorbell/last") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard let last = obj["last"] as? [String: Any],
                  let ts = last["ts"] as? Double else { return DoorbellLast(ts: 0, customerId: nil, name: nil) }
            return DoorbellLast(ts: ts,
                                customerId: last["custId"] as? String,
                                name: last["name"] as? String)
        } catch {
            return nil
        }
    }

    // MARK: 会话 Cookie 管理

    /// 清除本域会话 Cookie（URLSession 侧；WKWebView 侧由 WorkbenchController.clearWebData 清）
    static func clearSessionCookies() {
        let jar = HTTPCookieStorage.shared
        for cookie in jar.cookies ?? [] where cookie.domain.contains(Constants.workbenchHostSuffix) {
            jar.deleteCookie(cookie)
        }
    }
}
