import SwiftUI

// MARK: - 星链页签（品牌首页：图纸风状态台）

struct HomeView: View {
    @ObservedObject var store: WorkbenchStore
    @Binding var selection: WBTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 品牌区
                VStack(spacing: 10) {
                    BrandLogo(size: 84)
                    Text("星链")
                        .font(Strat.mono(40, weight: .heavy))
                        .tracking(6)
                        .foregroundColor(Color.wxText)
                    Text("STARLINK MATRIX · 内部版")
                        .font(Strat.mono(11, weight: .medium))
                        .tracking(3)
                        .foregroundColor(Color.wxSecondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 26)

                // 公告（服务端 /api/me.announcement）
                if !announcement.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("公告")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(Color.accent)
                        Text(announcement)
                            .font(.system(size: 14))
                            .foregroundColor(Color.wxText)
                    }
                    .inkPanel()
                    .padding(.horizontal, 16)
                }

                // 工况仪表行
                VStack(alignment: .leading, spacing: 0) {
                    statusRow("值班账号", store.me?.name.isEmpty == false ? store.me!.name : model.accountName,
                              sub: store.me?.username ?? "")
                    Divider().overlay(Color.wxSeparator)
                    statusRow("实时链路", realtimeLabel,
                              sub: "SSE · /api/events",
                              dot: realtimeColor)
                    Divider().overlay(Color.wxSeparator)
                    statusRow("当前入口", (store.base.replacingOccurrences(of: "https://", with: "")),
                              sub: "容灾三域名轮询")
                    Divider().overlay(Color.wxSeparator)
                    statusRow("会话有效期", expiryText, sub: expirySub)
                }
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
                .padding(.horizontal, 16)

                // 快捷入口
                HStack(spacing: 10) {
                    shortcutButton("工作台", icon: "bubble.left.and.bubble.right.fill",
                                   badge: store.totalUnreadCount) { selection = .workbench }
                    shortcutButton("码池", icon: "qrcode") { selection = .qr }
                    shortcutButton("我的", icon: "person.crop.circle.fill") { selection = .me }
                }
                .padding(.horizontal, 16)

                // 统计概览
                HStack(spacing: 10) {
                    StatChipView(title: "连接客户", value: "\(store.customers.count)")
                    StatChipView(title: "未读会话", value: "\(store.totalUnreadCount)", highlight: store.totalUnreadCount > 0)
                    StatChipView(title: "可用码", value: usableCountText, highlight: usableCountText == "0")
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
        }
        .background(Color.wxBackground.ignoresSafeArea())
    }

    @EnvironmentObject var model: AppModel

    private var announcement: String { store.me?.announcement ?? "" }

    private var realtimeLabel: String {
        switch store.realtime.state {
        case .connected: return "已连接"
        case .connecting: return "接入中"
        case .reconnecting: return "重连中"
        case .stopped: return "未启用"
        case .idle: return "待命"
        }
    }

    private var realtimeColor: Color {
        switch store.realtime.state {
        case .connected: return .statusOnline
        case .connecting, .reconnecting: return .wxWarn
        default: return .wxSecondaryText
        }
    }

    private var usableCountText: String {
        guard let s = store.qrStats else { return "—" }
        return "\(s.active + s.buffer)"
    }

    private var expiryText: String {
        guard let me = store.me else { return "—" }
        guard let ts = me.expiresAt, ts > 0 else { return "永久" }
        if me.expired { return "已过期" }
        return WBTime.full(ts)
    }

    private var expirySub: String {
        guard let me = store.me, let ts = me.expiresAt, ts > 0, !me.expired else { return "" }
        let left = ts - store.realtime.serverNowMs
        if left <= 0 { return "" }
        return "剩余 \(WBTime.fmtLeft(left))"
    }

    @ViewBuilder
    private func statusRow(_ title: String, _ value: String, sub: String, dot: Color? = nil) -> some View {
        HStack(spacing: 12) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            } else {
                Rectangle().fill(Color.inkLine).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Color.wxSecondaryText)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(Strat.mono(14, weight: .semibold))
                    .foregroundColor(Color.wxText)
                    .lineLimit(1)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Color.wxTertiaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func shortcutButton(_ title: String, icon: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(Color.accent)
                    Text(title)
                        .font(Strat.mono(13, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Color.wxText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 74)
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
                if badge > 0 {
                    UnreadBadge(count: badge)
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
