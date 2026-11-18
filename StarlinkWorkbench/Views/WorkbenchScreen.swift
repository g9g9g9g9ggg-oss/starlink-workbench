import SwiftUI
import WebKit

/// 工作台主屏：整页 WebView 本体 + 原生增强覆盖层（进度条/悬浮设置/横幅路由）
struct WorkbenchScreen: View {
    @ObservedObject var controller: WorkbenchController
    @EnvironmentObject var model: AppModel
    @AppStorage(Constants.hideFloatingButtonKey) private var hideFloatingButton = false

    var body: some View {
        ZStack {
            WebViewContainer(controller: controller)
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            if controller.progress > 0.02 && controller.progress < 0.99 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.brandGold)
                            .frame(width: geo.size.width * min(max(controller.progress, 0), 1),
                                   height: 2.5)
                    }
                }
                .frame(height: 2.5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !hideFloatingButton {
                Button {
                    model.showSettings = true
                } label: {
                    Image(systemName: "gearshape.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.gray.opacity(0.42))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                }
                .padding(.trailing, 14)
                .padding(.bottom, 88)
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openReception)) { _ in
            controller.goToReception()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMessage)) { _ in
            controller.goToReception()
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let controller: WorkbenchController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
