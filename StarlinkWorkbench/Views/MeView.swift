import SwiftUI
import PhotosUI

// MARK: - 我的页签（对齐演示页：头像卡 + 工作台设置/账号与安全/提醒/门铃守护/网络/关于）

struct MeView: View {
    @ObservedObject var store: WorkbenchStore
    @EnvironmentObject var model: AppModel

    @State private var showWorkbenchSettings = false
    @State private var showSecurity = false
    @State private var showAlerts = false
    @State private var showLegacySettings = false

    var body: some View {
        VStack(spacing: 0) {
            BigTitle(text: "我的")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 头像卡
                    HStack(spacing: 14) {
                        meAvatar
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.me?.name.isEmpty == false ? store.me!.name : model.accountName)
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundColor(Color.wxText)
                            Text("@\(store.me?.username ?? "—")")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundColor(Color.wxSecondaryText)
                            HStack(spacing: 6) {
                                StateChip(text: expiryChip, kind: expiryKind)
                                if let me = store.me, me.expiresAt ?? 0 > 0, !me.expired {
                                    StateChip(text: "剩余 \(WBTime.fmtLeft(me.expiresAt! - store.realtime.serverNowMs))",
                                              kind: .muted)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color.wxCell)
                    .cornerRadius(Strat.corner)
                    .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                        .strokeBorder(Color.inkLine, lineWidth: 1))

                    // 入口列表
                    VStack(spacing: 0) {
                        meRow("slider.horizontal.3", "工作台设置") { showWorkbenchSettings = true }
                        divider
                        meRow("lock.shield", "账号与安全") { showSecurity = true }
                        divider
                        meRow("bell.badge", "消息与门铃提醒") { showAlerts = true }
                        divider
                        meRow("waveform.path.ecg.rectangle", "门铃后台守护") { showLegacySettings = true }
                        divider
                        meRow("arrow.left.arrow.right", "网络与域名") { showLegacySettings = true }
                        divider
                        meRow("info.circle", "关于星链") { showLegacySettings = true }
                    }
                    .background(Color.wxCell)
                    .cornerRadius(Strat.corner)
                    .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                        .strokeBorder(Color.inkLine, lineWidth: 1))

                    // 域名诊断快览
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前入口")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(Color.accent)
                        ForEach(model.probeRows) { row in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(row.state == .ok ? Color.statusOnline :
                                          row.state == .fail ? Color.wxDanger : Color.wxTertiaryText.opacity(0.5))
                                    .frame(width: 7, height: 7)
                                Text(row.host.replacingOccurrences(of: "https://", with: ""))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundColor(Color.wxText)
                                if model.baseURL?.absoluteString == row.host {
                                    Text("当前")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color.accent)
                                }
                                Spacer()
                            }
                        }
                    }
                    .inkPanel()

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color.wxBackground.ignoresSafeArea())
        .sheet(isPresented: $showWorkbenchSettings) {
            WorkbenchSettingsSheet(store: store)
        }
        .sheet(isPresented: $showSecurity) {
            SecuritySheet(store: store)
        }
        .sheet(isPresented: $showAlerts) {
            AlertsSheet()
        }
        .sheet(isPresented: $showLegacySettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var meAvatar: some View {
        if let a = store.me?.avatarUrl, !a.isEmpty {
            RemoteImage(urlString: store.base + a, corner: Strat.corner, tap: nil, size: 58)
        } else {
            InitialAvatar(name: store.me?.name ?? model.accountName, size: 58)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.wxSeparator).frame(height: 0.5).padding(.leading, 44)
    }

    @ViewBuilder
    private func meRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color.accent)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(Color.wxText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color.wxTertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var expiryChip: String {
        guard let me = store.me else { return "—" }
        guard let ts = me.expiresAt, ts > 0 else { return "永久有效" }
        return me.expired ? "已过期" : "有效期 \(WBTime.dayStamp(ts))"
    }

    private var expiryKind: WBStateKind {
        guard let me = store.me else { return .muted }
        if me.expired { return .bad }
        guard let ts = me.expiresAt else { return .good }
        let left = ts - store.realtime.serverNowMs
        if left < 3 * 86400_000 { return .warn }
        return .good
    }
}

// MARK: - 工作台设置（PUT /api/settings：名称/头像/Logo/欢迎语/码尾字标）

struct WorkbenchSettingsSheet: View {
    @ObservedObject var store: WorkbenchStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var welcome = ""
    @State private var footer = ""
    @State private var avatarUrl = ""
    @State private var logoUrl = ""
    @State private var saving = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var logoItem: PhotosPickerItem?

    var body: some View {
        DrawerSheet(title: "工作台设置") {
            VStack(alignment: .leading, spacing: 12) {
                Text("品牌形象")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)

                HStack(spacing: 14) {
                    VStack(spacing: 6) {
                        if avatarUrl.isEmpty {
                            InitialAvatar(name: name.isEmpty ? "客" : name, size: 60)
                        } else {
                            RemoteImage(urlString: store.base + avatarUrl, corner: Strat.corner, tap: nil, size: 60)
                        }
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            Text("头像")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.wxLink)
                        }
                        .buttonStyle(.plain)
                        .onChange(of: avatarItem) { item in
                            guard let item else { return }
                            avatarItem = nil
                            Task { await uploadPicked(item, isLogo: false) }
                        }
                    }
                    VStack(spacing: 6) {
                        if logoUrl.isEmpty {
                            ZStack {
                                RoundedRectangle(cornerRadius: Strat.corner)
                                    .fill(Color.wxBackground)
                                    .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                                        .strokeBorder(Color.inkLine, lineWidth: 1))
                                Image(systemName: "star")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color.brandGold)
                            }
                            .frame(width: 60, height: 60)
                        } else {
                            RemoteImage(urlString: store.base + logoUrl, corner: Strat.corner, tap: nil, size: 60)
                        }
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Text("Logo")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.wxLink)
                        }
                        .buttonStyle(.plain)
                        .onChange(of: logoItem) { item in
                            guard let item else { return }
                            logoItem = nil
                            Task { await uploadPicked(item, isLogo: true) }
                        }
                    }
                    Spacer()
                }
            }
            .inkPanel()

            VStack(alignment: .leading, spacing: 12) {
                Text("接待配置")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                InkField(label: "工作台名称", text: $name)
                InkField(label: "默认欢迎语", text: $welcome)
                InkField(label: "二维码底部字标（≤24字）", text: $footer)
            }
            .inkPanel()

            Button {
                Task {
                    saving = true
                    do {
                        try await WBAPI.putSettings(base: store.base,
                                                    fields: ["name": name,
                                                             "welcomeDefault": welcome,
                                                             "qrFooterText": footer])
                        await store.reloadMe()
                        store.model?.showToast("已保存")
                        dismiss()
                    } catch let e as WBApiError {
                        store.model?.showToast(e.message)
                    } catch {
                        store.model?.showToast("保存失败")
                    }
                    saving = false
                }
            } label: {
                InkButtonLabel(title: saving ? "保存中…" : "保存", ready: !saving)
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
        .onAppear(perform: load)
    }

    private func load() {
        Task {
            if let s = try? await WBAPI.settings(base: store.base) {
                name = s.name
                welcome = s.welcomeDefault
                footer = s.qrFooterText
                avatarUrl = s.avatarUrl
                logoUrl = s.logoUrl
            }
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem, isLogo: Bool) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let file = (data, isLogo ? "logo.png" : "avatar.jpg", "image/jpeg")
        do {
            try await WBAPI.putSettings(base: store.base, fields: [:],
                                        avatar: isLogo ? nil : file,
                                        logo: isLogo ? file : nil)
            store.model?.showToast(isLogo ? "Logo 已更新" : "头像已更新")
            load()
        } catch let e as WBApiError {
            store.model?.showToast(e.message)
        } catch {
            store.model?.showToast("上传失败")
        }
    }
}

// MARK: - 账号与安全（设备会话/踢下线/改密）

struct SecuritySheet: View {
    @ObservedObject var store: WorkbenchStore
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [WBSession] = []
    @State private var loading = true
    @State private var showChange = false
    @State private var oldPw = ""
    @State private var newPw = ""
    @State private var newPw2 = ""
    @State private var changing = false

    var body: some View {
        DrawerSheet(title: "账号与安全") {
            VStack(alignment: .leading, spacing: 10) {
                Text("登录设备（\(sessions.count)）")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                if loading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(sessions, id: \.id) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("\(s.browser) · \(s.os)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color.wxText)
                                if s.current {
                                    StateChip(text: "本机", kind: .good)
                                }
                                Spacer()
                                if !s.current {
                                    Button {
                                        Task {
                                            try? await WBAPI.kickSession(base: store.base, sid: s.id)
                                            await loadSessions()
                                            store.model?.showToast("已下线该设备")
                                        }
                                    } label: {
                                        Text("下线")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(Color.wxDanger)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Text("\(s.device) · \(s.ip) · 登录 \(WBTime.full(s.loginAt))")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundColor(Color.wxTertiaryText)
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(Color.wxSeparator)
                    }
                }
            }
            .inkPanel()

            VStack(alignment: .leading, spacing: 10) {
                Text("批量管理")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                InkRowButton(title: "下线其他全部设备") {
                    Task {
                        try? await WBAPI.kickOthers(base: store.base)
                        await loadSessions()
                        store.model?.showToast("已下线其他设备")
                    }
                }
            }
            .inkPanel()

            VStack(alignment: .leading, spacing: 12) {
                Text("修改密码")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                SecureField("当前密码", text: $oldPw)
                    .inkFieldType()
                SecureField("新密码（≥6位）", text: $newPw)
                    .inkFieldType()
                SecureField("再次输入新密码", text: $newPw2)
                    .inkFieldType()
                Button {
                    Task {
                        guard newPw == newPw2 else {
                            store.model?.showToast("两次新密码不一致")
                            return
                        }
                        guard newPw.count >= 6 else {
                            store.model?.showToast("新密码至少 6 位")
                            return
                        }
                        changing = true
                        do {
                            try await WBAPI.changePassword(base: store.base, oldPassword: oldPw, newPassword: newPw)
                            store.model?.showToast("密码已修改")
                            oldPw = ""; newPw = ""; newPw2 = ""
                        } catch let e as WBApiError {
                            store.model?.showToast(e.message)
                        } catch {
                            store.model?.showToast("修改失败")
                        }
                        changing = false
                    }
                } label: {
                    InkButtonLabel(title: changing ? "提交中…" : "修改密码", ready: !changing && !oldPw.isEmpty && newPw.count >= 6)
                }
                .buttonStyle(.plain)
                .disabled(changing)
            }
            .inkPanel()
        }
        .onAppear {
            Task { await loadSessions() }
        }
    }

    private func loadSessions() async {
        loading = true
        sessions = (try? await WBAPI.securitySessions(base: store.base)) ?? []
        loading = false
    }
}

extension View {
    /// 墨线密码框样式
    func inkFieldType() -> some View {
        self
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.wxBackground)
            .cornerRadius(Strat.corner)
            .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                .strokeBorder(Color.inkLine, lineWidth: 1))
    }
}

// MARK: - 消息与门铃提醒（声音/震动/闪光/免打扰，对齐网页 alert 设置键）

struct AlertsSheet: View {
    @AppStorage("xl_sound") private var soundOn = true
    @AppStorage("xl_vibrate") private var vibrateOn = true
    @AppStorage("xl_flash") private var flashOn = false
    @AppStorage("xl_snd_msg") private var sndMsg = "default"
    @AppStorage("xl_snd_online") private var sndOnline = "off"
    @AppStorage("xl_snd_scan") private var sndScan = "off"
    @AppStorage("xl_dnd_on") private var dndOn = false
    @AppStorage("xl_dnd_s") private var dndStart = 23
    @AppStorage("xl_dnd_e") private var dndEnd = 8

    var body: some View {
        DrawerSheet(title: "消息与门铃提醒") {
            VStack(alignment: .leading, spacing: 12) {
                Text("总开关")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                Toggle(isOn: $soundOn) { rowLabel("提示音", sub: "全局声音开关") }
                    .toggleStyle(SwitchToggleStyle(tint: Color.accent))
                Toggle(isOn: $vibrateOn) { rowLabel("震动", sub: "新消息 [350,200,350] · 门铃三段重震") }
                    .toggleStyle(SwitchToggleStyle(tint: Color.accent))
                Toggle(isOn: $flashOn) { rowLabel("闪光灯提醒", sub: "来电时闪烁（对齐安卓壳）") }
                    .toggleStyle(SwitchToggleStyle(tint: Color.accent))
            }
            .inkPanel()

            VStack(alignment: .leading, spacing: 12) {
                Text("分事件音效")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                soundPicker("新消息", selection: $sndMsg, excludeDoorbell: true, fallback: .dingDong)
                soundPicker("客户上线", selection: $sndOnline, excludeDoorbell: true, fallback: .off)
                soundPicker("新客户扫码", selection: $sndScan, excludeDoorbell: true, fallback: .off)
            }
            .inkPanel()

            VStack(alignment: .leading, spacing: 12) {
                Text("免打扰时段")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                Toggle(isOn: $dndOn) { rowLabel("启用免打扰", sub: "时段内不响铃不震动（通知保留）") }
                    .toggleStyle(SwitchToggleStyle(tint: Color.accent))
                if dndOn {
                    HStack(spacing: 10) {
                        Picker("开始", selection: $dndStart) {
                            ForEach(0..<24, id: \.self) { Text("\($0) 点").tag($0) }
                        }
                        .pickerStyle(.menu)
                        Text("至").font(.system(size: 12)).foregroundColor(Color.wxSecondaryText)
                        Picker("结束", selection: $dndEnd) {
                            ForEach(0..<24, id: \.self) { Text("\($0) 点").tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .inkPanel()
        }
    }

    private func rowLabel(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14)).foregroundColor(Color.wxText)
            Text(sub).font(.system(size: 10)).foregroundColor(Color.wxTertiaryText)
        }
    }

    @ViewBuilder
    private func soundPicker(_ title: String, selection: Binding<String>,
                             excludeDoorbell: Bool, fallback: SoundEngine.Kind) -> some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundColor(Color.wxText)
            Spacer()
            Picker("", selection: selection) {
                ForEach([SoundEngine.Kind.dingDong, .qq, .wechat, .knock, .cough, .off], id: \.rawValue) { kind in
                    Text(kind.title).tag(kind.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
    }
}
