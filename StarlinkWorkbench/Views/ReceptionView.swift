import SwiftUI

// MARK: - 工作台页签：会话列表（对齐网页 CustomerList 排版）

struct ReceptionView: View {
    @ObservedObject var store: WorkbenchStore
    @State private var searchInput = ""
    @State private var searchDebounce: Task<Void, Never>?
    @State private var deleteTarget: WBCustomer?

    var body: some View {
        VStack(spacing: 0) {
            BigTitle(text: "工作台")

            // 搜索 + 筛选
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(Color.wxTertiaryText)
                    TextField("搜索客户 / 备注 / 来源码", text: $searchInput)
                        .font(.system(size: 15))
                        .submitLabel(.search)
                    if !searchInput.isEmpty {
                        Button { searchInput = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color.wxTertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))

                HStack(spacing: 0) {
                    segmentButton("全部", key: "all")
                    segmentButton("未读", key: "unread",
                                  count: store.customers.filter { $0.unread > 0 }.count)
                }
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if !store.refreshError.isEmpty {
                Text(store.refreshError)
                    .font(.footnote)
                    .foregroundColor(Color.wxDanger)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.customers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 34))
                                .foregroundColor(Color.wxTertiaryText)
                            Text("暂无会话")
                                .font(.system(size: 13))
                                .foregroundColor(Color.wxSecondaryText)
                        }
                        .padding(.top, 80)
                    }
                    ForEach(store.customers, id: \.id) { customer in
                        CustomerRow(customer: customer) {
                            _ = store.openChat(customer)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteTarget = customer
                            } label: {
                                Label("解除连接", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .refreshable {
                await store.refreshCustomers(silent: true)
            }
        }
        .background(Color.wxBackground.ignoresSafeArea())
        .onChange(of: searchInput) { value in
            searchDebounce?.cancel()
            searchDebounce = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                store.customerSearch = value
                await store.refreshCustomers(silent: true)
            }
        }
        .sheet(item: $deleteTarget) { customer in
            DeleteCustomerSheet(store: store, customer: customer)
                .presentationDetents([.height(230)])
        }
    }

    @ViewBuilder
    private func segmentButton(_ title: String, key: String, count: Int = 0) -> some View {
        let active = store.customerFilter == key
        Button {
            guard store.customerFilter != key else { return }
            store.customerFilter = key
            Task { await store.refreshCustomers(silent: true) }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                if key == "unread" && count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accent))
                }
            }
            .foregroundColor(active ? Color.wxText : Color.wxSecondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(active ? Color.wxBackground : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 会话行（名称+未读+在线+预览+chips）

struct CustomerRow: View {
    let customer: WBCustomer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    InitialAvatar(name: customer.displayName, size: 46)
                    Circle()
                        .fill(customer.online ? Color.statusOnline : Color.wxTertiaryText.opacity(0.4))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color.wxBackground, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }

                VStack(alignment: .leading, spacing: 5) {
                    // 行1：名称 + 未读 + 时间
                    HStack(spacing: 8) {
                        Text(customer.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.wxText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(WBTime.rel(customer.lastMessageAt != 0 ? customer.lastMessageAt : customer.createdAt))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Color.wxTertiaryText)
                    }

                    // 预览行
                    HStack(spacing: 6) {
                        if customer.unread > 0 {
                            UnreadBadge(count: customer.unread)
                        }
                        Text(preview)
                            .font(.system(size: 13))
                            .foregroundColor(customer.unread > 0 ? Color.wxText : Color.wxSecondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(presenceText(online: customer.online,
                                          onlineAt: 0,
                                          lastSeenAt: customer.lastSeenAt))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundColor(customer.online ? Color.statusOnline : Color.wxTertiaryText)
                    }

                    // chips：来源 / 金额 / 地区 / 备注
                    HStack(spacing: 6) {
                        chip(qrChip)
                        if !customer.amount.isEmpty { chip(customer.amount, muted: false) }
                        if !customer.region.isEmpty { chip(customer.region) }
                        if !customer.note.isEmpty { chip("📝 \(customer.note)") }
                    }
                    .lineLimit(1)
                }
            }
            .padding(12)
            .background(Color.wxCell)
            .cornerRadius(Strat.corner)
            .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                .strokeBorder(Color.inkLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var preview: String {
        let prefix = customer.lastSender == "operator" ? "你：" : ""
        return prefix + (customer.lastPreview.isEmpty ? "（新客户，等待接入）" : customer.lastPreview)
    }

    private var qrChip: (String, Bool) {
        if customer.qrName.isEmpty { return ("直接进入", true) }
        if customer.qrDeleted { return ("\(customer.qrName) · 已删除", true) }
        return (customer.qrName, false)
    }

    @ViewBuilder
    private func chip(_ content: String, muted: Bool = true) -> some View {
        if !content.isEmpty {
            Text(content)
                .font(.system(size: 10))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.wxBackground)
                .foregroundColor(muted ? Color.wxSecondaryText : Color.wxText)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine.opacity(0.4), lineWidth: 1))
        }
    }
}

// MARK: - 解除连接确认（对齐网页 DELETE /api/customers/:id 二次确认）

struct DeleteCustomerSheet: View {
    @ObservedObject var store: WorkbenchStore
    let customer: WBCustomer
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("解除连接")
                .font(Strat.mono(18, weight: .heavy))
                .tracking(2)
                .foregroundColor(Color.wxDanger)
            Text("将与「\(customer.displayName)」的连接解除，聊天记录与图片一并删除，不可恢复。")
                .font(.system(size: 13))
                .foregroundColor(Color.wxSecondaryText)
            HStack(spacing: 10) {
                InkRowButton(title: "取消") { dismiss() }
                Button {
                    working = true
                    Task {
                        try? await WBAPI.deleteCustomer(base: store.base, cid: customer.id)
                        await store.refreshCustomers(silent: true)
                        if store.chat?.cid == customer.id { store.closeChat() }
                        store.model?.showToast("已解除连接") // model 为 weak，直接用 store 不便；改为本地提示
                        dismiss()
                        working = false
                    }
                } label: {
                    Text(working ? "处理中…" : "解除")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: Strat.corner)
                            .fill(Color.wxDanger))
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
        .padding(18)
        .background(Color.wxBackground.ignoresSafeArea())
    }
}
