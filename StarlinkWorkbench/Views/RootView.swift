import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .connecting, .failed:
                ConnectView()
            case .login:
                LoginView()
            case .workbench:
                if let store = model.store {
                    RootTabView(store: store)
                } else {
                    WorkbenchScreen(controller: model.webController)
                }
            }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                ShellBannerView(banner: banner) {
                    if case .doorbell = banner {
                        model.openDoorbellTarget()
                    }
                    model.banner = nil
                }
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastCapsule(text: toast)
                    .padding(.bottom, 84)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.banner)
        .animation(.easeInOut(duration: 0.25), value: model.toast)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }
}

/// 顶部横幅（微信式预览浮条的原生形态）
struct ShellBannerView: View {
    let banner: ShellBanner
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if case .doorbell = banner {
                    Circle().fill(Color.brandGold).frame(width: 8, height: 8)
                }
                Text(banner.text)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.86))
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

/// 底部轻提示
struct ToastCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .padding(.horizontal, 40)
    }
}
