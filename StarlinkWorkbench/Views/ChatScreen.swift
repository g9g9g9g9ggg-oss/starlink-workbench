import SwiftUI
import PhotosUI

// MARK: - 聊天屏（对齐网页 ChatPanel：气泡/引用/回执/天分组/长按菜单/快捷面板）

struct ChatScreen: View {
    @ObservedObject var store: WorkbenchStore
    @ObservedObject var state: ChatState
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var quote: WBMessage?
    @State private var showProfile = false
    @State private var showQuick = false
    @State private var quickTexts: [WBQuickText] = []
    @State private var quickImages: [WBQuickImage] = []
    @State private var quickSearch = ""
    @State private var photoPicker: PhotosPickerItem?
    @State private var viewerImage: WBMessage?
    @State private var flashTarget: String?
    @State private var uploading = false

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().overlay(Color.inkLine)
            messageList
            Divider().overlay(Color.inkLine)
            composer
        }
        .background(Color.wxBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .sheet(isPresented: $showProfile) {
            ProfileSheet(store: store, state: state)
        }
        .sheet(isPresented: $showQuick) {
            QuickPanelSheet(store: store, texts: $quickTexts, images: $quickImages,
                            search: $quickSearch,
                            onPickText: { text in
                                if draft.isEmpty { draft = text } else { draft += "\n" + text }
                            },
                            onSendText: { text in
                                store.sendText(text, quote: nil)
                            },
                            onSendImage: { fileId in
                                store.sendImage(fileId: fileId, quote: nil)
                            })
        }
        .sheet(item: $viewerImage) { msg in
            ImageViewerSheet(store: store, message: msg)
        }
        .onChange(of: photoPicker) { item in
            guard let item else { return }
            photoPicker = nil
            Task { await uploadAndSend(item: item) }
        }
    }

    // MARK: 头部（名称 + 在线 + 资料入口）

    private var chatHeader: some View {
        HStack(spacing: 10) {
            Button {
                store.closeChat()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.wxText)
            }
            .buttonStyle(.plain)

            Button {
                showProfile = true
            } label: {
                HStack(spacing: 10) {
                    InitialAvatar(name: state.customer.displayName, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.customer.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.wxText)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(state.customer.online ? Color.statusOnline : Color.wxTertiaryText.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(presenceText(online: state.customer.online,
                                              onlineAt: state.detail.map { _ in 0 } ?? 0,
                                              lastSeenAt: state.customer.lastSeenAt))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundColor(state.customer.online ? Color.statusOnline : Color.wxTertiaryText)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(Color.wxTertiaryText)
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.wxCell)
    }

    // MARK: 消息流

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if state.loading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("加载消息…")
                                .font(.footnote)
                                .foregroundColor(Color.wxSecondaryText)
                        }
                        .padding(.top, 60)
                    }
                    let groups = dayGroups
                    ForEach(groups, id: \.0) { day, items in
                        VStack(spacing: 2) {
                            Text(day)
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundColor(Color.wxTertiaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.wxCell)
                                .cornerRadius(Strat.corner)
                                .padding(.vertical, 8)
                            ForEach(items, id: \.id) { msg in
                                MessageBubble(message: msg, flash: flashTarget == msg.id) {
                                    viewerImage = msg
                                }
                                .id(msg.id)
                                .contextMenu { messageMenu(for: msg) }
                            }
                        }
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: state.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: flashTarget) { target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    flashTarget = nil
                }
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
        }
    }

    /// 按天分组（今天/昨天/M月d日）
    private var dayGroups: [(String, [WBMessage])] {
        var out: [(String, [WBMessage])] = []
        for msg in state.messages {
            let label = WBTime.dayLabel(msg.createdAt)
            if out.last?.0 == label {
                out[out.count - 1].1.append(msg)
            } else {
                out.append((label, [msg]))
            }
        }
        return out
    }

    // MARK: 长按菜单（对齐网页：引用→复制→复制链接→保存→撤回→删除）

    @ViewBuilder
    private func messageMenu(for msg: WBMessage) -> some View {
        if msg.status != "recalled" && !msg.pending && !msg.failed {
            Button {
                quote = msg
            } label: {
                Label("引用", systemImage: "quote.opening")
            }
            Button {
                UIPasteboard.general.string = msg.isImage ? "[图片] \(fileURL(msg).absoluteString)" : msg.content
                model.showToast("已复制")
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            if !msg.isImage, containsURL(msg.content) {
                Button {
                    UIPasteboard.general.string = firstURL(msg.content)
                    model.showToast("链接已复制")
                } label: {
                    Label("复制链接", systemImage: "link")
                }
            }
            if msg.isImage {
                Button {
                    saveImage(msg)
                } label: {
                    Label("保存图片", systemImage: "square.and.arrow.down")
                }
            }
            if msg.isOperator && (msg.status == "ok" || msg.status == "read") {
                Button {
                    store.recall(msg)
                } label: {
                    Label("撤回", systemImage: "arrow.uturn.backward")
                }
            }
        }
        if msg.failed {
            Button {
                store.retryPending(msg)
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                store.removePending(msg)
            } label: {
                Label("移除", systemImage: "trash")
            }
        } else if !msg.pending {
            Button(role: .destructive) {
                store.deleteMessage(msg)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: 输入区（引用条 + 快捷 + 图片 + 发送）

    private var composer: some View {
        VStack(spacing: 0) {
            if let q = quote {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.accent).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.quoteName.isEmpty ? (q.isOperator ? "我" : state.customer.displayName) : q.quoteName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.accent)
                        Text(q.isImage ? "[图片]" : q.content)
                            .font(.system(size: 12))
                            .foregroundColor(Color.wxSecondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        quote = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.wxTertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.wxCell)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await loadQuickIfNeeded() }
                    showQuick = true
                } label: {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 20))
                        .foregroundColor(Color.wxSecondaryText)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $photoPicker, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                        .foregroundColor(uploading ? Color.wxTertiaryText : Color.wxSecondaryText)
                }
                .disabled(uploading)

                TextField("输入消息…", text: $draft, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.wxCell)
                    .cornerRadius(Strat.corner)
                    .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                        .strokeBorder(Color.inkLine, lineWidth: 1))
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 19))
                        .foregroundColor(canSend ? Color.accent : Color.wxTertiaryText)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.wxCell)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        let q = quote
        quote = nil
        store.sendText(text, quote: q)
    }

    // MARK: 图片发送与查看

    private func fileURL(_ msg: WBMessage) -> URL {
        URL(string: store.base + msg.fileUrl) ?? URL(fileURLWithPath: "/")
    }

    private func uploadAndSend(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.showToast("读取图片失败")
            return
        }
        uploading = true
        defer { uploading = false }
        do {
            let res = try await WBAPI.upload(base: store.base, fileData: data,
                                             fileName: "image.jpg", mime: "image/jpeg", kind: "chat")
            let fileId = res.sOrEmpty("id")
            guard !fileId.isEmpty else {
                model.showToast("上传失败")
                return
            }
            store.sendImage(fileId: fileId, quote: quote)
            quote = nil
        } catch let e as WBApiError {
            model.showToast(e.message)
        } catch {
            model.showToast("上传失败")
        }
    }

    private func saveImage(_ msg: WBMessage) {
        Task {
            let url = fileURL(msg)
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let img = UIImage(data: data)
                let saver = ImageSaver()
                saver.write(img: img)
                model.showToast(img == nil ? "保存失败" : "已存入相册")
            } catch {
                model.showToast("保存失败")
            }
        }
    }

    private func loadQuickIfNeeded() async {
        guard quickTexts.isEmpty && quickImages.isEmpty else { return }
        quickTexts = (try? await WBAPI.quickTexts(base: store.base, search: "", category: "")) ?? []
        quickImages = (try? await WBAPI.quickImages(base: store.base, search: "", category: "")) ?? []
    }

    private func containsURL(_ text: String) -> Bool {
        text.range(of: "https?://", options: .regularExpression) != nil
    }

    private func firstURL(_ text: String) -> String {
        guard let m = text.range(of: "https?://\\S+", options: .regularExpression) else { return text }
        return String(text[m])
    }
}

// MARK: - 气泡（微信式：己方右侧暖纸/对方左侧白 + 回执 + 引用条）

struct MessageBubble: View {
    let message: WBMessage
    let flash: Bool
    var onImageTap: () -> Void

    private var isMe: Bool { message.isOperator }
    private var pendingAlpha: Double { message.pending ? 0.55 : 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer(minLength: 48) }
            if !isMe {
                InitialAvatar(name: message.sender == "system" ? "系" : "", size: 30)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                bubbleBody
                // 回执行（己方）：pending 旋转 / ok 单钩 / read 双钩 / failed 重试
                if isMe {
                    receiptRow
                }
            }
            .opacity(pendingAlpha)

            if !isMe { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .background(flash ? Color.brandGold.opacity(0.16) : Color.clear)
        .animation(.easeInOut(duration: 0.3), value: flash)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if message.status == "recalled" {
            Text(message.isOperator ? "你撤回了一条消息" : "对方撤回了一条消息")
                .font(.system(size: 12))
                .italic()
                .foregroundColor(Color.wxTertiaryText)
                .padding(.vertical, 6)
        } else if message.status == "deleted" {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !message.quoteName.isEmpty || !message.quoteText.isEmpty {
                    quoteBar
                }
                if message.isImage {
                    imageBody
                } else {
                    textBody
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.inkLine.opacity(0.35), lineWidth: 1)
            )
        }
    }

    /// 引用条（点击定位原消息由父层 flashTarget 处理；此处仅快照展示）
    @ViewBuilder
    private var quoteBar: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(message.quoteName.isEmpty ? "引用" : message.quoteName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.wxLink)
            if !message.quoteText.isEmpty {
                Text(message.quoteText)
                    .font(.system(size: 12))
                    .foregroundColor(Color.wxSecondaryText)
                    .lineLimit(2)
            }
        }
        .padding(6)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Color.wxBackground.opacity(0.7))
        .cornerRadius(2)
        .overlay(RoundedRectangle(cornerRadius: 2)
            .strokeBorder(Color.inkLine.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private var textBody: some View {
        Text(messageText(message.content))
            .font(.system(size: 15))
            .foregroundColor(Color.wxText)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var imageBody: some View {
        Group {
            if message.pending {
                Rectangle()
                    .fill(Color.wxCell)
                    .frame(width: 150, height: 150)
                    .overlay(ProgressView().tint(Color.wxSecondaryText))
                    .cornerRadius(4)
            } else {
                RemoteImage(urlString: imageURL, corner: 4, tap: onImageTap, size: 150)
            }
        }
    }

    private var imageURL: String {
        if message.fileUrl.hasPrefix("http") { return message.fileUrl }
        return storeBase + message.fileUrl
    }

    private var storeBase: String {
        // 气泡在 ChatScreen 内使用，base 经 RemoteImage 的完整 URL 传入
        ImageBaseHolder.shared.base
    }

    @ViewBuilder
    private var receiptRow: some View {
        HStack(spacing: 4) {
            if message.failed {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(Color.wxDanger)
                    Text("发送失败")
                        .font(.system(size: 10))
                        .foregroundColor(Color.wxDanger)
                }
            } else if message.pending {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    if message.status == "read" {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .offset(x: -5, y: 0)
                    }
                }
                .foregroundColor(Color.wxTertiaryText)
                Text(WBTime.clock(message.createdAt))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Color.wxTertiaryText)
            }
        }
    }

    private func messageText(_ content: String) -> AttributedString {
        var attr = AttributedString(content)
        attr.foregroundColor = Color.wxText
        // URL 高亮（linkify）
        if let regex = try? NSRegularExpression(pattern: "https?://\\S+") {
            let ns = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                if let r = Range(m.range, in: attr) {
                    attr[r].foregroundColor = .wxLink
                    attr[r].underlineStyle = .single
                }
            }
        }
        return attr
    }
}

/// 全局 base 持有（气泡图片 URL 拼接用）
@MainActor
final class ImageBaseHolder {
    static let shared = ImageBaseHolder()
    var base: String = ""
}

// MARK: - 远程图片（会话 cookie 鉴权加载 + 点击回调）

struct RemoteImage: View {
    let urlString: String
    var corner: CGFloat = Strat.corner
    var tap: (() -> Void)?
    /// 固定边长；nil = 填满外层可用空间
    var size: CGFloat? = 150

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.wxCell
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Color.wxSecondaryText)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: size == nil ? .infinity : nil,
               maxHeight: size == nil ? .infinity : nil)
        .clipped()
        .cornerRadius(corner)
        .overlay(RoundedRectangle(cornerRadius: corner)
            .strokeBorder(Color.inkLine.opacity(0.35), lineWidth: 1))
        .onAppear { load() }
        .onTapGesture { tap?() }
    }

    private func load() {
        let urlStr = urlString
        Task {
            guard let url = URL(string: urlStr) else { return }
            do {
                var req = URLRequest(url: url)
                req.cachePolicy = .returnCacheDataElseLoad
                let (data, _) = try await URLSession.shared.data(for: req)
                withAnimation(.easeIn(duration: 0.15)) {
                    image = UIImage(data: data)
                }
            } catch {
                // 占位保持
            }
        }
    }
}

// MARK: - 图片灯箱

struct ImageViewerSheet: View {
    @ObservedObject var store: WorkbenchStore
    let message: WBMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RemoteImage(urlString: fullURL, corner: 0, size: nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .navigationTitle("图片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                if let url = URL(string: fullURL),
                                   let (data, _) = try? await URLSession.shared.data(from: url),
                                   let img = UIImage(data: data) {
                                    ImageSaver().write(img: img)
                                    store.model?.showToast("已存入相册")
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }

    private var fullURL: String {
        message.fileUrl.hasPrefix("http") ? message.fileUrl : store.base + message.fileUrl
    }
}

// MARK: - 相册保存（Info.plist 已有 AddUsage 描述）

final class ImageSaver: NSObject {
    func write(img: UIImage?) {
        guard let img else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }
}
