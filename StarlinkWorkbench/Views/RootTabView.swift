import SwiftUI

// MARK: - 四页签骨架（对齐演示页 pv-tabbar：星链/工作台/码池/我的）

enum WBTab: Int, CaseIterable {
    case home = 0, workbench = 1, qr = 2, me = 3

    var title: String {
        switch self {
        case .home: return "星链"
        case .workbench: return "工作台"
        case .qr: return "码池"
        case .me: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .home: return "star.fill"
        case .workbench: return "bubble.left.and.bubble.right.fill"
        case .qr: return "qrcode"
        case .me: return "person.crop.circle.fill"
        }
    }
}

struct RootTabView: View {
    @ObservedObject var store: WorkbenchStore
    @EnvironmentObject var model: AppModel
    @State private var selection: WBTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.wxBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch selection {
                    case .home: HomeView(store: store, selection: $selection)
                    case .workbench: ReceptionView(store: store)
                    case .qr: QrPoolView(store: store)
                    case .me: MeView(store: store)
                    }
                }
                .frame(maxHeight: .infinity)

                if store.chat == nil {
                    tabBar
                }
            }

            // 聊天打开时隐藏 TabBar（微信式全屏会话）
            if let chat = store.chat {
                ChatScreen(store: store, state: chat)
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.chat == nil)
        .onReceive(NotificationCenter.default.publisher(for: .openReception)) { _ in
            selection = .workbench
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMessage)) { note in
            selection = .workbench
            if let cid = note.object as? String {
                store.openChatById(cid)
            }
        }
        .onChange(of: store.totalUnreadCount) { unread in
            if selection == .home && unread > 0 {
                // 首页徽标驱动，无需处理
            }
        }
    }

    // MARK: 仪表风底部导航（图纸语言：纸面 + 墨线顶边 + 强调色标记条）

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.inkLine)
                .frame(height: 1)
            HStack(spacing: 0) {
                tabButton(.home)
                tabButton(.workbench, badge: store.totalUnreadCount)
                tabButton(.qr)
                tabButton(.me)
            }
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
        .background(Color.wxCell)
    }

    @ViewBuilder
    private func tabButton(_ tab: WBTab, badge: Int = 0) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 21, weight: selection == tab ? .semibold : .regular))
                        .foregroundColor(selection == tab ? Color.accent : Color.wxSecondaryText)
                    if badge > 0 {
                        UnreadBadge(count: badge)
                            .offset(x: 12, y: -6)
                    }
                }
                Text(tab.title)
                    .font(.system(size: 10, weight: selection == tab ? .semibold : .regular))
                    .foregroundColor(selection == tab ? Color.wxText : Color.wxSecondaryText)
                // 选中标记条（对齐 .pv-tab.on::before）
                Rectangle()
                    .fill(selection == tab ? Color.accent : Color.clear)
                    .frame(width: 26, height: 3)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
