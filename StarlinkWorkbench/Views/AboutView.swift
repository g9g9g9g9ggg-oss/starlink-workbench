import SwiftUI

/// 关于页：品牌卡片 + 版本对照
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    BrandLogo(size: 72)
                    VStack(spacing: 4) {
                        Text("星链工作台")
                            .font(.title3.bold())
                            .foregroundColor(Color.wxText)
                        Text("STARLINK MATRIX · 客户接待工作台")
                            .font(.caption)
                            .foregroundColor(Color.wxSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .listRowBackground(Color.wxBackground)

            Section("版本") {
                row("iOS 原生版", "2.0.0 (20)")
                row("对标 Android 版", "1.6.1 (versionCode 8)")
                row("功能基线", "与网页版/桌面版完全一致")
            }

            Section("架构") {
                row("实现", "纯原生 SwiftUI（四页签 + SSE 实时 + 门铃守护）")
                row("实时层", "原生 SSE /api/events + 轮询兜底")
                row("后台守护", "BGAppRefresh + 可选音频保活")
                row("提示音", "离线合成音源（与 WebAudio 同参数）")
                row("视觉", "STRATUM 图纸风（纸面/墨线/朱砂）")
            }

            Section {
                Text("服务器与网页版零改动。本应用仅做壳层增强：探活接入、原生登录、门铃守护、系统通知、闪光灯与震动桥、外链与下载、会话隔离与安全退出。")
                    .font(.footnote)
                    .foregroundColor(Color.wxSecondaryText)
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundColor(Color.wxSecondaryText)
        }
    }
}
