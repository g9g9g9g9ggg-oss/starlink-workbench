import SwiftUI

// MARK: - 码池页签（对齐网页 QrCodesPage：统计卡 + 列表 + 12h/1h 过期倒计时 + 全套操作）

struct QrPoolView: View {
    @ObservedObject var store: WorkbenchStore
    @State private var tickNow = Date()
    @State private var showCreate = false
    @State private var filter = "usable"

    private let filters: [(String, String)] = [
        ("usable", "可用"), ("active", "有效中"), ("buffer", "缓冲期"),
        ("paused", "已停用"), ("revoked", "已撤销"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            BigTitle(text: "码池")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 统计卡
                    if let s = store.qrStats {
                        HStack(spacing: 8) {
                            StatChipView(title: "可用", value: "\(s.active + s.buffer)", highlight: true)
                            StatChipView(title: "有效中", value: "\(s.active)")
                            StatChipView(title: "缓冲期", value: "\(s.buffer)")
                        }
                        HStack(spacing: 8) {
                            StatChipView(title: "停用", value: "\(s.paused)")
                            StatChipView(title: "撤销", value: "\(s.revoked)")
                            StatChipView(title: "扫码客户", value: "\(s.customerTotal)")
                        }
                        if let poolLeft = s.poolLeft {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.wxSecondaryText)
                                Text("上游码池余量 \(poolLeft)")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundColor(Color.wxSecondaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                    }

                    // 筛选
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.0) { key, label in
                                Button {
                                    filter = key
                                    Task { await reloadFilter(key) }
                                } label: {
                                    Text(label)
                                        .font(.system(size: 12, weight: filter == key ? .semibold : .regular))
                                        .foregroundColor(filter == key ? Color.accent : Color.wxSecondaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.wxCell)
                                        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                                            .strokeBorder(filter == key ? Color.accent : Color.inkLine.opacity(0.5),
                                                          lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 列表
                    LazyVStack(spacing: 10) {
                        if filteredList.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 34))
                                    .foregroundColor(Color.wxTertiaryText)
                                Text("此筛选下暂无二维码")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.wxSecondaryText)
                            }
                            .padding(.top, 60)
                        }
                        ForEach(filteredList, id: \.id) { qr in
                            QrCard(store: store, qr: qr, tickNow: tickNow)
                        }
                    }

                    Color.clear.frame(height: 70)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color.wxBackground.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            Button {
                showCreate = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("新建二维码")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: Strat.corner).fill(Color.accent))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.bottom, 14)
        }
        .sheet(isPresented: $showCreate) {
            QrCreateWizard(store: store)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            tickNow = now
        }
    }

    private var filteredList: [WBQRCode] {
        switch filter {
        case "usable": return store.qrList.filter { $0.state == "active" || $0.state == "buffer" }
        default: return store.qrList.filter { $0.state == filter }
        }
    }

    private func reloadFilter(_ key: String) async {
        // 本地过滤即可（列表已全量拉过）；撤销/停用等操作后 refreshQR 已重拉
    }
}

// MARK: - 二维码卡片（裸码风格 + 状态 + 倒计时 + 操作）

struct QrCard: View {
    @ObservedObject var store: WorkbenchStore
    let qr: WBQRCode
    let tickNow: Date
    @State private var showActions = false
    @State private var confirmDelete = false
    @State private var viewerQR: WBQRCode?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // 码图（点击放大）
                Button {
                    viewerQR = qr
                } label: {
                    RemoteImage(urlString: store.base + "/api/qrcodes/\(qr.id)/image.png",
                                corner: Strat.corner, tap: nil, size: 96)
                }
                .buttonStyle(.plain)
                .disabled(qr.state == "deleted")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(qr.name)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(Color.wxText)
                            .lineLimit(1)
                        StateChip(text: stateLabel, kind: stateKind)
                        Spacer(minLength: 0)
                    }
                    if !qr.note.isEmpty {
                        Text(qr.note)
                            .font(.system(size: 11))
                            .foregroundColor(Color.wxSecondaryText)
                            .lineLimit(1)
                    }
                    Text("码标 \(qr.entryCode)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Color.wxTertiaryText)
                    if usable {
                        Text(leftText)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundColor(qr.state == "buffer" ? Color.wxWarn : Color.statusOnline)
                    }
                    Text("扫码 \(qr.customerCount) 人 · \(WBTime.dayStamp(qr.createdAt))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Color.wxTertiaryText)
                }
            }

            // 操作行
            HStack(spacing: 8) {
                actionButton("详情", primary: false) { showActions = true }
                if qr.state == "active" || qr.state == "buffer" {
                    actionButton("停用", primary: false) {
                        store.qrAction("pause", id: qr.id, confirmToast: "已停用")
                    }
                } else if qr.state == "paused" {
                    actionButton("恢复", primary: false) {
                        store.qrAction("resume", id: qr.id, confirmToast: "已恢复")
                    }
                }
                if qr.state == "active" || qr.state == "buffer" || qr.state == "paused" {
                    actionButton("换新码", primary: false) {
                        store.qrAction("replace", id: qr.id, confirmToast: "已换发新码")
                    }
                    actionButton("撤销", primary: false) {
                        store.qrAction("revoke", id: qr.id, confirmToast: "已撤销")
                    }
                }
                Spacer(minLength: 0)
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(Color.wxDanger)
                        .frame(width: 34, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                            .strokeBorder(Color.wxDanger.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.wxCell)
        .cornerRadius(Strat.corner)
        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
            .strokeBorder(Color.inkLine, lineWidth: 1))
        .sheet(item: $viewerQR) { q in
            QrViewerSheet(store: store, qr: q)
        }
        .sheet(isPresented: $showActions) {
            QrDetailSheet(store: store, qr: qr)
        }
        .confirmationDialog("删除二维码「\(qr.name)」？扫码记录保留", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.qrDelete(id: qr.id)
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var usable: Bool { qr.state == "active" || qr.state == "buffer" }

    private var stateLabel: String {
        qr.stateLabel.isEmpty ? qr.state : qr.stateLabel
    }

    private var stateKind: WBStateKind {
        switch qr.state {
        case "active": return .good
        case "buffer": return .warn
        case "paused": return .muted
        case "revoked", "deleted": return .bad
        default: return .muted
        }
    }

    /// 剩余倒计时（leftMs - 本地流逝，服务端时钟基准由 store.realtime.serverNowMs 提供）
    private var leftText: String {
        let elapsed = Int64(Date().timeIntervalSince(store.qrFetchedAt) * 1000)
        let left = qr.leftMs - elapsed
        if left <= 0 { return "已到期" }
        let prefix = qr.state == "buffer" ? "缓冲期剩余 " : "剩余 "
        return prefix + WBTime.fmtLeft(left)
    }

    @ViewBuilder
    private func actionButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.wxText)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.wxBackground)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 码图放大（含下载/分享）

struct QrViewerSheet: View {
    @ObservedObject var store: WorkbenchStore
    let qr: WBQRCode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    RemoteImage(urlString: store.base + "/api/qrcodes/\(qr.id)/image.png",
                                corner: Strat.corner, tap: nil, size: 280)
                    Text(qr.name)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(Color.wxText)
                    Text(qr.entryUrl)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(Color.wxLink)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button {
                        UIPasteboard.general.string = qr.entryUrl
                        store.model?.showToast("入口链接已复制")
                    } label: {
                        Text("复制入口链接")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.accent)
                            .frame(height: 38)
                            .frame(maxWidth: .infinity)
                            .background(Color.wxCell)
                            .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                                .strokeBorder(Color.inkLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .background(Color.wxBackground.ignoresSafeArea())
            .navigationTitle("二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - 详情抽屉（编辑 + 源数据 + 预览）

struct QrDetailSheet: View {
    @ObservedObject var store: WorkbenchStore
    let qr: WBQRCode
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var welcome = ""
    @State private var footer = ""
    @State private var style = "jadeWhite"
    @State private var kefu = true
    @State private var saving = false
    @State private var sources: [(String, String, String)] = []   // id/name/时间

    private let styles: [(String, String)] = [
        ("jadeWhite", "白玉金边"), ("aurum", "墨金典藏"), ("emerald", "墨绿鎏金"),
        ("starry", "星夜藏蓝"), ("minimal", "极简金丝"),
    ]

    var body: some View {
        DrawerSheet(title: "二维码详情") {
            // 预览
            VStack(alignment: .leading, spacing: 10) {
                Text("当前样式预览")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                RemoteImage(urlString: previewURL, corner: Strat.corner, tap: nil, size: 180)
                    .frame(maxWidth: .infinity)
            }
            .inkPanel()

            // 编辑
            VStack(alignment: .leading, spacing: 12) {
                Text("编辑")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                InkField(label: "名称（≤30字）", text: $name)
                InkField(label: "备注", text: $note)
                InkField(label: "欢迎语覆盖", text: $welcome, placeholder: "留空用平台默认")
                InkField(label: "底部字标（≤24字）", text: $footer)
                VStack(alignment: .leading, spacing: 8) {
                    Text("样式")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(Color.wxSecondaryText)
                    HStack(spacing: 8) {
                        ForEach(styles, id: \.0) { key, label in
                            Button {
                                style = key
                            } label: {
                                Text(label)
                                    .font(.system(size: 12, weight: style == key ? .semibold : .regular))
                                    .foregroundColor(style == key ? Color.accent : Color.wxSecondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.wxBackground)
                                    .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                                        .strokeBorder(style == key ? Color.accent : Color.inkLine.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Toggle(isOn: $kefu) {
                    Text("在线客服标志")
                        .font(.system(size: 13))
                }
                .toggleStyle(SwitchToggleStyle(tint: Color.accent))
            }
            .inkPanel()

            Button {
                Task {
                    saving = true
                    do {
                        _ = try await WBAPI.qrUpdate(base: store.base, id: qr.id, name: name,
                                                     note: note, welcomeOverride: welcome,
                                                     themeStyle: style, kefu: kefu, footer: footer,
                                                     logoFileId: nil)
                        await store.refreshQR(silent: true)
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
                InkButtonLabel(title: saving ? "保存中…" : "保存修改", ready: !saving)
            }
            .buttonStyle(.plain)
            .disabled(saving)

            // 源数据（最近扫码客户）
            VStack(alignment: .leading, spacing: 10) {
                Text("扫码来源（\(sources.count)）")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.accent)
                if sources.isEmpty {
                    Text("暂无扫码记录")
                        .font(.system(size: 12))
                        .foregroundColor(Color.wxTertiaryText)
                } else {
                    ForEach(sources, id: \.0) { sid, sname, stime in
                        HStack {
                            Text(sname)
                                .font(.system(size: 13))
                                .foregroundColor(Color.wxText)
                            Spacer()
                            Text(stime)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundColor(Color.wxTertiaryText)
                        }
                    }
                }
            }
            .inkPanel()
        }
        .onAppear(perform: load)
    }

    private var previewURL: String {
        var comps = URLComponents(string: store.base + "/api/qrcodes/preview.png")
        comps?.queryItems = [
            URLQueryItem(name: "code", value: qr.entryCode),
            URLQueryItem(name: "p", value: qr.urlPath),
            URLQueryItem(name: "s", value: style),
            URLQueryItem(name: "kefu", value: kefu ? "1" : "0"),
        ]
        if !footer.isEmpty { comps?.queryItems?.append(URLQueryItem(name: "footer", value: footer)) }
        return comps?.url?.absoluteString ?? ""
    }

    private func load() {
        name = qr.name
        note = qr.note
        welcome = qr.welcomeOverride
        style = qr.themeStyle.isEmpty ? "jadeWhite" : qr.themeStyle
        kefu = qr.themeKefu
        footer = qr.themeFooter
        Task {
            if let obj = try? await WBAPI.jsonCall(base: store.base, path: "api/qrcodes/\(qr.id)/source") as? [String: Any] {
                let list = obj.arr("customers")
                sources = list.prefix(50).map { d in
                    (d.sOrEmpty("id"), d.sOrEmpty("display_name"), WBTime.full(d.i("created_at") ?? 0))
                }
            }
        }
    }
}

// MARK: - 新建向导（对齐网页 QrWizard 三步）

struct QrCreateWizard: View {
    @ObservedObject var store: WorkbenchStore
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var name = ""
    @State private var note = ""
    @State private var welcome = ""
    @State private var footer = "扫码咨询"
    @State private var style = "jadeWhite"
    @State private var kefu = true
    @State private var draftCode = ""
    @State private var draftPath = ""
    @State private var creating = false

    private let styles: [(String, String)] = [
        ("jadeWhite", "白玉金边"), ("aurum", "墨金典藏"), ("emerald", "墨绿鎏金"),
        ("starry", "星夜藏蓝"), ("minimal", "极简金丝"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepIndicator

                    if step == 1 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("备注信息")
                                .font(Strat.mono(17, weight: .heavy))
                                .tracking(2)
                                .foregroundColor(Color.wxText)
                            InkField(label: "名称（≤30字，必填）", text: $name)
                            InkField(label: "备注", text: $note)
                            InkField(label: "欢迎语覆盖", text: $welcome, placeholder: "留空用平台默认")
                        }
                        .inkPanel()
                    } else if step == 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("样式外观")
                                .font(Strat.mono(17, weight: .heavy))
                                .tracking(2)
                                .foregroundColor(Color.wxText)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("码面样式")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1)
                                    .foregroundColor(Color.wxSecondaryText)
                                HStack(spacing: 8) {
                                    ForEach(styles, id: \.0) { key, label in
                                        Button {
                                            style = key
                                        } label: {
                                            Text(label)
                                                .font(.system(size: 12, weight: style == key ? .semibold : .regular))
                                                .foregroundColor(style == key ? Color.accent : Color.wxSecondaryText)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(Color.wxBackground)
                                                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                                                    .strokeBorder(style == key ? Color.accent : Color.inkLine.opacity(0.5), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            InkField(label: "底部字标（≤24字）", text: $footer)
                            Toggle(isOn: $kefu) {
                                Text("在线客服标志")
                                    .font(.system(size: 13))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.accent))
                        }
                        .inkPanel()
                        if !draftCode.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("预览（未启用）")
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(2)
                                    .foregroundColor(Color.accent)
                                RemoteImage(urlString: previewURL, corner: Strat.corner, tap: nil, size: 200)
                                    .frame(maxWidth: .infinity)
                            }
                            .inkPanel()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("领取确认")
                                .font(Strat.mono(17, weight: .heavy))
                                .tracking(2)
                                .foregroundColor(Color.wxText)
                            HStack {
                                Text("名称").font(.system(size: 12)).foregroundColor(Color.wxSecondaryText)
                                Spacer()
                                Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(Color.wxText)
                            }
                            HStack {
                                Text("样式").font(.system(size: 12)).foregroundColor(Color.wxSecondaryText)
                                Spacer()
                                Text(styles.first { $0.0 == style }?.1 ?? style)
                                    .font(.system(size: 13)).foregroundColor(Color.wxText)
                            }
                            HStack {
                                Text("有效期").font(.system(size: 12)).foregroundColor(Color.wxSecondaryText)
                                Spacer()
                                Text("12 小时 + 1 小时缓冲")
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundColor(Color.wxText)
                            }
                            RemoteImage(urlString: previewURL, corner: Strat.corner, tap: nil, size: 200)
                                .frame(maxWidth: .infinity)
                        }
                        .inkPanel()
                    }

                    HStack(spacing: 10) {
                        if step > 1 {
                            InkRowButton(title: "上一步") {
                                step -= 1
                            }
                        }
                        Button {
                            nextStep()
                        } label: {
                            InkButtonLabel(title: step == 3 ? (creating ? "制码中…" : "领取启用") : "下一步",
                                           ready: stepReady)
                        }
                        .buttonStyle(.plain)
                        .disabled(!stepReady || creating)
                    }
                }
                .padding(16)
            }
            .background(Color.wxBackground.ignoresSafeArea())
            .navigationTitle("新建二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(creating)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { i in
                HStack(spacing: 4) {
                    Text("\(i)")
                        .font(Strat.mono(11, weight: .heavy).monospacedDigit())
                        .foregroundColor(i <= step ? Color.white : Color.wxTertiaryText)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: Strat.corner)
                            .fill(i <= step ? Color.accent : Color.wxCell))
                    if i < 3 {
                        Rectangle()
                            .fill(i < step ? Color.accent : Color.inkLine.opacity(0.4))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Spacer()
        }
    }

    private var stepReady: Bool {
        switch step {
        case 1: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private var previewURL: String {
        var comps = URLComponents(string: store.base + "/api/qrcodes/preview.png")
        comps?.queryItems = [
            URLQueryItem(name: "code", value: draftCode),
            URLQueryItem(name: "p", value: draftPath),
            URLQueryItem(name: "s", value: style),
            URLQueryItem(name: "kefu", value: kefu ? "1" : "0"),
        ]
        if !footer.isEmpty { comps?.queryItems?.append(URLQueryItem(name: "footer", value: footer)) }
        return comps?.url?.absoluteString ?? ""
    }

    private func nextStep() {
        if step < 3 {
            if step == 1, draftCode.isEmpty {
                Task {
                    if let draft = try? await WBAPI.qrDraft(base: store.base) {
                        draftCode = draft.entryCode
                        draftPath = draft.urlPath
                    }
                }
            }
            step += 1
        } else {
            creating = true
            Task {
                do {
                    if draftCode.isEmpty,
                       let draft = try? await WBAPI.qrDraft(base: store.base) {
                        draftCode = draft.entryCode
                        draftPath = draft.urlPath
                    }
                    _ = try await WBAPI.qrCreate(base: store.base, name: name.trimmingCharacters(in: .whitespaces),
                                                 note: note, welcomeOverride: welcome,
                                                 themeStyle: style, kefu: kefu, footer: footer,
                                                 logoFileId: nil, entryCode: draftCode, urlPath: draftPath)
                    await store.refreshQR(silent: true)
                    store.model?.showToast("二维码已启用 · 有效 12 小时")
                    dismiss()
                } catch let e as WBApiError {
                    store.model?.showToast(e.message)
                } catch {
                    store.model?.showToast("制码失败")
                }
                creating = false
            }
        }
    }
}
