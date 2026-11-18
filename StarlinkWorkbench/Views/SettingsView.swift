import SwiftUI
import UserNotifications

/// 原生设置页（微信式分区列表）：账号安全 / 门铃守护 / 提示音试听 / 域名诊断 / 通用
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.hideFloatingButtonKey) private var hideFloatingButton = false
    @State private var notificationsAuthorized = false
    @State private var showLogoutConfirm = false
    @State private var savedPassword = KeychainStore.load() != nil

    var body: some View {
        NavigationStack {
            List {
                accountSection
                guardSection
                soundSection
                networkSection
                generalSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear(perform: refreshNotificationStatus)
    }

    // MARK: - 账号与安全

    private var accountSection: some View {
        Section("账号与安全") {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Color.wxGreen.opacity(0.85))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.accountName.isEmpty ? "未登录（网页登录模式）" : model.accountName)
                        .font(.body.weight(.medium))
                        .foregroundColor(Color.wxText)
                    Text(model.accountName.isEmpty ? "后台守护不可用，建议使用原生登录" : "工作台会话 · 独立隔离")
                        .font(.caption)
                        .foregroundColor(Color.wxSecondaryText)
                }
                Spacer()
            }

            HStack {
                Text("记住密码")
                Spacer()
                Text(savedPassword ? "已保存于 Keychain" : "未保存")
                    .font(.footnote)
                    .foregroundColor(Color.wxSecondaryText)
            }

            if savedPassword {
                Button {
                    KeychainStore.clear()
                    savedPassword = false
                    model.showToast("已清除本机保存的密码")
                } label: {
                    Text("清除本机保存的密码")
                        .foregroundColor(Color.wxLink)
                }
            }

            Button {
                showLogoutConfirm = true
            } label: {
                Text("退出登录")
                    .font(.body.weight(.medium))
                    .foregroundColor(Color.wxDanger)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .confirmationDialog("退出后将吊销服务器会话并清除本机 Cookie/缓存/密码", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    Task { await model.logout() }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 门铃后台守护

    private var guardSection: some View {
        Section {
            DoorbellGuardStatusView(guardService: model.doorbellGuard)

            Picker("守护模式", selection: Binding(
                get: { model.keepAliveMode },
                set: { model.keepAliveMode = $0 }
            )) {
                Text("标准").tag(false)
                Text("强·音频保活").tag(true)
            }
            .pickerStyle(.menu)
        } header: {
            Text("门铃后台守护")
        } footer: {
            Text("标准：系统调度（BGAppRefresh，时机由 iOS 决定）；强：静音音频保活 + 3 秒轮询（对齐安卓前台守护，耗电略增）。前台时由网页实时提醒接管，自动停用守护，避免重复响铃。")
        }
    }

    // MARK: - 提示音

    private var soundSection: some View {
        Section {
            Button {
                refreshNotificationStatus()
                Task {
                    _ = await AlertCenter.shared.requestAuthorization()
                    refreshNotificationStatus()
                }
            } label: {
                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(notificationsAuthorized ? "已允许" : "未允许")
                        .font(.footnote)
                        .foregroundColor(notificationsAuthorized ? Color.wxGreen : Color.wxDanger)
                }
            }

            ForEach([SoundEngine.Kind.dingDong, .qq, .wechat, .knock, .cough, .doorbell], id: \.rawValue) { kind in
                Button {
                    SoundEngine.shared.play(kind)
                    HapticEngine.vibrate([80])
                } label: {
                    HStack {
                        Text(kind.title)
                            .foregroundColor(Color.wxText)
                        Spacer()
                        Image(systemName: "speaker.wave.2")
                            .font(.footnote)
                            .foregroundColor(Color.wxSecondaryText)
                    }
                }
            }
        } header: {
            Text("提示音（点击试听）")
        } footer: {
            Text("各事件（新消息/客户上线/新客户扫码）的具体音效选择在工作台「设置」页内管理，与网页版完全一致；本列表用于试听与后台通知音。")
        }
    }

    // MARK: - 网络与域名

    private var networkSection: some View {
        Section {
            ForEach(model.probeRows) { row in
                Button {
                    switchHost(row.host)
                } label: {
                    HStack {
                        Circle()
                            .fill(color(for: row.state))
                            .frame(width: 9, height: 9)
                        Text(row.host.replacingOccurrences(of: "https://", with: ""))
                            .foregroundColor(Color.wxText)
                        Spacer()
                        if model.baseURL?.absoluteString == row.host {
                            Text("当前")
                                .font(.caption)
                                .foregroundColor(Color.wxGreen)
                        }
                    }
                }
            }

            Button {
                reprobe()
            } label: {
                HStack {
                    Image(systemName: "dot.radar")
                    Text("重新检测全部入口")
                        .foregroundColor(Color.wxLink)
                }
            }
        } header: {
            Text("网络与域名")
        } footer: {
            Text("点击域名可切换入口；服务器迁移后更新工程内 Constants.hosts 即可（与桌面版域名常量一致）。")
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        Section("通用") {
            Button {
                model.webController.clearWebData()
                model.showToast("网页缓存已清除")
            } label: {
                Text("清除网页缓存")
                    .foregroundColor(Color.wxLink)
            }

            Toggle("隐藏悬浮设置按钮", isOn: $hideFloatingButton)

            NavigationLink {
                AboutView()
            } label: {
                HStack {
                    Text("关于星链工作台")
                    Spacer()
                    Text(versionText)
                        .font(.footnote)
                        .foregroundColor(Color.wxSecondaryText)
                }
            }
        }
    }

    // MARK: - 辅助

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(short) (\(build))"
    }

    private func color(for state: ProbeState) -> Color {
        switch state {
        case .pending, .probing: return Color.wxSecondaryText.opacity(0.5)
        case .ok: return Color.wxGreen
        case .fail: return Color.wxDanger
        }
    }

    private func switchHost(_ host: String) {
        model.enterWorkbench(base: host, path: "/reception")
        model.showToast("已切换至 \(host.replacingOccurrences(of: "https://", with: ""))")
    }

    private func reprobe() {
        Task {
            let hosts = model.probeRows.map(\.host)
            let _ = await ServerProber.probeAll(hosts) { index, state in
                model.probeRows[index].state = state
            }
            model.showToast("检测完成")
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
}

/// 守护状态子视图（独立观察 DoorbellGuard）
struct DoorbellGuardStatusView: View {
    @ObservedObject var guardService: DoorbellGuard

    var body: some View {
        Group {
            HStack {
                Text("守护状态")
                Spacer()
                Text(guardService.guardActive ? "运行中" : "待命（前台接管）")
                    .font(.footnote)
                    .foregroundColor(guardService.guardActive ? Color.wxGreen : Color.wxSecondaryText)
            }
            HStack {
                Text("会话桥接")
                Spacer()
                Text(guardService.bridged ? "已桥接" : "未桥接")
                    .font(.footnote)
                    .foregroundColor(guardService.bridged ? Color.wxGreen : Color.wxWarn)
            }
            HStack {
                Text("上次检查")
                Spacer()
                if let poll = guardService.lastPoll {
                    Text(poll.formatted(date: .omitted, time: .standard))
                        .font(.footnote)
                        .foregroundColor(Color.wxSecondaryText)
                } else {
                    Text("—")
                        .font(.footnote)
                        .foregroundColor(Color.wxSecondaryText)
                }
            }
            HStack {
                Text("已提醒门铃")
                Spacer()
                Text("\(guardService.hitCount) 次")
                    .font(.footnote)
                    .foregroundColor(Color.wxSecondaryText)
            }
        }
    }
}
