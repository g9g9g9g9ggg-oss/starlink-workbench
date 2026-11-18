import SwiftUI

// MARK: - 资料抽屉（对齐网页 ProfilePanel：只读核心 + 可编辑字段 + 跟进状态 + 标签）

struct ProfileSheet: View {
    @ObservedObject var store: WorkbenchStore
    @ObservedObject var state: ChatState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var amount = ""
    @State private var region = ""
    @State private var note = ""
    @State private var specialNote1 = ""
    @State private var specialNote2 = ""
    @State private var followStatus = "new"
    @State private var tags: [String] = []
    @State private var tagDraft = ""
    @State private var savingField = ""

    var body: some View {
        DrawerSheet(title: "客户资料") {
            // 头部
            HStack(spacing: 12) {
                InitialAvatar(name: state.customer.displayName, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.customer.displayName.isEmpty ? "客户" : state.customer.displayName)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(Color.wxText)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(state.customer.online ? Color.statusOnline : Color.wxTertiaryText.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(presenceText(online: state.customer.online,
                                          onlineAt: 0,
                                          lastSeenAt: state.customer.lastSeenAt))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(state.customer.online ? Color.statusOnline : Color.wxTertiaryText)
                    }
                }
                Spacer()
                StateChip(text: followLabel(followStatus), kind: followKind)
            }

            if let d = state.detail {
                // 只读核心
                VStack(alignment: .leading, spacing: 10) {
                    profileTitle("核心信息")
                    roLine("来源二维码", d.qrName.isEmpty ? "直接进入" : d.qrName)
                    roLine("设备", d.device.isEmpty ? "—" : d.device)
                    HStack(spacing: 0) {
                        roLine("IP", d.ip.isEmpty ? "—" : d.ip)
                    }
                    if !state.ipLocation.isEmpty {
                        roLine("IP 归属地", state.ipLocation)
                    }
                }
                .inkPanel()

                // 时间与统计
                VStack(alignment: .leading, spacing: 10) {
                    profileTitle("时间与统计")
                    roLine("消息数", "\(d.messageCount)")
                    roLine("入口码", d.entryCode)
                    roLine("首次进入", WBTime.full(d.createdAt))
                    roLine("最近消息", WBTime.full(d.lastMessageAt))
                }
                .inkPanel()
            }

            // 可编辑字段（每项独立确定）
            VStack(alignment: .leading, spacing: 12) {
                profileTitle("可编辑资料")
                editableField("客户名称", text: $displayName, key: "displayName")
                editableField("成交金额", text: $amount, key: "amount")
                editableField("地区", text: $region, key: "region")
                editableField("备注", text: $note, key: "note")
                editableField("特殊备注 1", text: $specialNote1, key: "specialNote1")
                editableField("特殊备注 2", text: $specialNote2, key: "specialNote2")
            }
            .inkPanel()

            // 跟进状态（Select 即存）
            VStack(alignment: .leading, spacing: 10) {
                profileTitle("跟进状态")
                HStack(spacing: 8) {
                    ForEach([("new", "新客户"), ("following", "跟进中"),
                             ("negotiated", "已谈成"), ("paid", "已付款"), ("closed", "已关闭")], id: \.0) { key, label in
                        Button {
                            guard followStatus != key else { return }
                            followStatus = key
                            Task { await saveField(["followStatus": key]) }
                        } label: {
                            Text(label)
                                .font(.system(size: 12, weight: followStatus == key ? .semibold : .regular))
                                .foregroundColor(followStatus == key ? Color.accent : Color.wxSecondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.wxBackground)
                                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                                    .strokeBorder(followStatus == key ? Color.accent : Color.inkLine.opacity(0.5),
                                                  lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .inkPanel()

            // 标签（≤10 个 × 20 字）
            VStack(alignment: .leading, spacing: 10) {
                profileTitle("标签（\(tags.count)/10）")
                FlowChips(tags: tags) { tag in
                    tags.removeAll { $0 == tag }
                    Task { await saveField(["tags": tags]) }
                }
                HStack(spacing: 8) {
                    TextField("新标签（≤20字）", text: $tagDraft)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(Color.wxBackground)
                        .cornerRadius(Strat.corner)
                        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                            .strokeBorder(Color.inkLine, lineWidth: 1))
                    Button {
                        let t = tagDraft.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, t.count <= 20, tags.count < 10 else { return }
                        tags.append(t)
                        tagDraft = ""
                        Task { await saveField(["tags": tags]) }
                    } label: {
                        Text("添加")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .inkPanel()

            // 危险操作
            InkRowButton(title: "解除连接（删除聊天与资料）", danger: true) {
                dismiss()
                NotificationCenter.default.post(name: .sheetDismissedRequest, object: state.cid)
            }
        }
        .onAppear(perform: loadFromState)
    }

    // MARK: 辅助

    private func loadFromState() {
        displayName = state.customer.displayName
        amount = state.customer.amount
        region = state.customer.region
        note = state.customer.note
        specialNote1 = state.customer.specialNote1
        specialNote2 = state.customer.specialNote2
        followStatus = state.customer.followStatus
        tags = state.customer.tags
    }

    @ViewBuilder
    private func editableField(_ label: String, text: Binding<String>, key: String) -> some View {
        let dirty = text.wrappedValue != originalValue(key: key)
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(Color.wxSecondaryText)
                Spacer()
                if dirty {
                    Button {
                        let value = text.wrappedValue
                        Task { await saveField([key: value]) }
                    } label: {
                        Text(savingField == key ? "保存中…" : "确定")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(savingField == key)
                }
            }
            TextField(label, text: text)
                .font(.system(size: 15))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Color.wxBackground)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
        }
    }

    private func originalValue(key: String) -> String {
        switch key {
        case "displayName": return state.customer.displayName
        case "amount": return state.customer.amount
        case "region": return state.customer.region
        case "note": return state.customer.note
        case "specialNote1": return state.customer.specialNote1
        case "specialNote2": return state.customer.specialNote2
        default: return ""
        }
    }

    @MainActor
    private func saveField(_ fields: [String: Any]) async {
        savingField = fields.keys.first ?? ""
        do {
            try await WBAPI.patchCustomer(base: store.base, cid: state.cid, fields: fields)
            if let n = fields["displayName"] as? String { state.customer.displayName = n }
            if let n = fields["amount"] as? String { state.customer.amount = n }
            if let n = fields["region"] as? String { state.customer.region = n }
            if let n = fields["note"] as? String { state.customer.note = n }
            if let n = fields["specialNote1"] as? String { state.customer.specialNote1 = n }
            if let n = fields["specialNote2"] as? String { state.customer.specialNote2 = n }
            if let n = fields["followStatus"] as? String { state.customer.followStatus = n }
            if let n = fields["tags"] as? [String] { state.customer.tags = n }
            store.model?.showToast("已保存")
        } catch let e as WBApiError {
            store.model?.showToast(e.message)
        } catch {
            store.model?.showToast("保存失败")
        }
        savingField = ""
    }

    private func roLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(Color.wxSecondaryText)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 13).monospacedDigit())
                .foregroundColor(Color.wxText)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func profileTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .tracking(2)
            .foregroundColor(Color.accent)
    }

    private var followLabel: (String) -> String {
        { key in
            switch key {
            case "new": return "新客户"
            case "following": return "跟进中"
            case "negotiated": return "已谈成"
            case "paid": return "已付款"
            case "closed": return "已关闭"
            default: return key
            }
        }
    }

    private var followKind: WBStateKind {
        switch followStatus {
        case "new": return .muted
        case "following": return .warn
        case "negotiated", "paid": return .good
        default: return .muted
        }
    }
}

extension Notification.Name {
    /// 资料抽屉请求删除会话（转给 ReceptionView 弹确认）
    static let sheetDismissedRequest = Notification.Name("starlink.sheetDeleteCustomer")
}

// MARK: - 标签流式排列

struct FlowChips: View {
    let tags: [String]
    let onDelete: (String) -> Void

    var body: some View {
        if tags.isEmpty {
            Text("暂无标签")
                .font(.system(size: 12))
                .foregroundColor(Color.wxTertiaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 6) {
                        Text(tag)
                            .font(.system(size: 12))
                            .foregroundColor(Color.wxText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.wxBackground)
                            .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                                .strokeBorder(Color.inkLine, lineWidth: 1))
                        Button {
                            onDelete(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.wxTertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
