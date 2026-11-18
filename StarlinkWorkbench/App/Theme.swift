import SwiftUI
import UIKit

// MARK: - STRATUM 设计令牌（图纸/仪表控制台）
// 纸面 + 墨线 + 直角 + 等宽数字 + 单一强调色。与原型 `原型/星链工作台-原生控件演示.html` 皮肤层一一对应。

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    // 浅色（默认）：暖纸面
    static let wxBackground = Color(hex: 0xF2F1EC)   // 纸面
    static let wxCell = Color.white                  // 面板
    static let wxText = Color(hex: 0x101014)         // 墨
    static let wxSecondaryText = Color(hex: 0x5A5A66)
    static let wxTertiaryText = Color(hex: 0x9A9AA4)
    static let wxLink = Color(hex: 0x576B95)
    static let wxFieldBackground = Color.white       // 输入框白底墨线
    static let wxDanger = Color(hex: 0xC93A2E)       // 朱砂（同强调色）
    static let wxWarn = Color(hex: 0xE6A23C)
    static let wxSeparator = Color(hex: 0xD9D9DE)

    // 强调色：朱砂（CTA / 焦点 / 标记线）
    static let stratumAccent = Color(hex: 0xC93A2E)

    // 语义（在线状态等，保持可辨识）
    static let statusOnline = Color(hex: 0x0E7C4A)

    // 深色模式（恒明长庚 → 深色模式）：黑底鎏金
    static let dkBackground = Color(hex: 0x0A0C10)
    static let dkCell = Color(hex: 0x12151B)
    static let dkText = Color(hex: 0xEDEEF2)
    static let dkSecondaryText = Color(hex: 0x8E93A0)
    static let dkAccent = Color(hex: 0xE8C36A)       // 鎏金

    // 墨线（边框）：浅色=墨，深色=浅描边
    static var inkLine: Color {
        UITraitCollection.current.userInterfaceStyle == .dark
            ? Color(hex: 0xEDEEF2, alpha: 0.55)
            : Color(hex: 0x101014, alpha: 0.92)
    }
    static var inkSolid: Color {
        UITraitCollection.current.userInterfaceStyle == .dark
            ? Color(hex: 0xEDEEF2)
            : Color(hex: 0x101014)
    }
}

// 兼容旧命名（工程内既有引用不动）
extension Color {
    static var wxGreen: Color { .stratumAccent }          // 强调色接管原绿色位
    static var wxBubbleOut: Color {
        UITraitCollection.current.userInterfaceStyle == .dark
            ? Color(hex: 0x2C2A1E)
            : Color(hex: 0xEFE7D4)                  // 暖纸气泡
    }
    static var brandBlack: Color { .inkSolid }     // 墨块按钮
    static var brandGold: Color { Color(hex: 0xE8C36A) }
    static var brandGoldBright: Color { Color(hex: 0xF2D28A) }
}

// MARK: - STRATUM 组件规约

enum Strat {
    /// 直角：全 App 统一 2pt
    static let corner: CGFloat = 2
    /// 等宽字体（标题 / 数字 / 按钮文案）
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// 墨线面板：STRATUM 标准容器（直角 + 1pt 墨线 + 面板底）
struct InkPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.wxCell)
            .cornerRadius(Strat.corner)
            .overlay(
                RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1)
            )
    }
}

/// 大标题：等宽 + 左侧强调色标记块（对齐原型 .big-title）
struct BigTitle: View {
    let text: String
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.stratumAccent)
                .frame(width: 6, height: 34)
            Text(text)
                .font(Strat.mono(30, weight: .heavy))
                .tracking(4)
                .foregroundColor(Color.wxText)
                .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.wxBackground)
    }
}

/// 墨块主按钮（登录 / 主 CTA）：等宽字 + 宽字距，就绪时转强调色
struct InkButtonLabel: View {
    let title: String
    var ready: Bool = true
    var body: some View {
        Text(title)
            .font(Strat.mono(17, weight: .semibold))
            .tracking(6)
            .foregroundColor(ready ? Color.white : Color.white.opacity(0.75))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Strat.corner)
                    .fill(ready ? Color.stratumAccent : Color(hex: 0xB8B8BE))
            )
    }
}

/// 微信风格行容器：面板底 + 内边距
struct WXRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.wxCell)
    }
}

extension View {
    func wxRow() -> some View { modifier(WXRow()) }
    func inkPanel() -> some View { modifier(InkPanel()) }
}

/// 品牌徽标（与 AppIcon 同源视觉：金色星链）
struct BrandLogo: View {
    var size: CGFloat = 120
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [Color.brandGold.opacity(0.35), Color.clear],
                                   center: .center, startRadius: size * 0.2, endRadius: size * 0.7)
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .opacity(glow ? 1 : 0.55)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [Color.brandGoldBright, Color.brandGold],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Color.brandGold.opacity(0.6), radius: glow ? 18 : 8)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.2))
                .foregroundStyle(Color.brandGoldBright)
                .offset(x: size * 0.3, y: -size * 0.3)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}
