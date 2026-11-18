import AVFoundation

/// 提示音引擎：音源为按网页版 WebAudio 合成参数离线生成的同款 wav（tools/gen_assets.py）。
/// 前台试听/本地提醒播放；后台系统通知使用同名 wav 作为 UNNotificationSound。
final class SoundEngine {
    enum Kind: String, CaseIterable {
        case dingDong = "default"
        case qq = "qq"
        case wechat = "wechat"
        case knock = "knock"
        case cough = "cough"
        case doorbell = "doorbell"
        case off = "off"

        var title: String {
            switch self {
            case .dingDong: return "叮咚 · 默认消息"
            case .qq: return "滴答 · 高频消息"
            case .wechat: return "铃铛 · 清脆双音"
            case .knock: return "敲门 · 三声木叩"
            case .cough: return "轻咳 · 两声提醒"
            case .doorbell: return "门铃 · 前台长铃"
            case .off: return "关闭"
            }
        }
    }

    static let shared = SoundEngine()
    private var players: [Kind: AVAudioPlayer] = [:]

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func player(for kind: Kind) -> AVAudioPlayer? {
        if let p = players[kind] { return p }
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "wav") else { return nil }
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        players[kind] = p
        return p
    }

    /// 播放（点按即响，与网页版设置页试听一致）
    func play(_ kind: Kind) {
        guard kind != .off else { return }
        activateSession()
        guard let p = player(for: kind) else { return }
        p.currentTime = 0
        p.play()
    }

    /// 音频保活：循环播放近静音音频（强守护模式，替代安卓前台服务）
    func startKeepAlive() -> AVAudioPlayer? {
        activateSession()
        guard let url = Bundle.main.url(forResource: "silent", withExtension: "wav") else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.numberOfLoops = -1
        p?.volume = 0.0001
        p?.play()
        return p
    }
}
