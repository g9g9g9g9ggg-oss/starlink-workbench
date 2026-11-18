import SwiftUI

// MARK: - 时间（北京时间，对齐网页版 relTime/fullTime）

enum WBTime {
    static let cn = TimeZone(identifier: "Asia/Shanghai")!

    private static func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    /// 刚刚 / N分钟前 / N小时前 / 昨天 / MM-DD
    static func rel(_ ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let d = date(ms)
        let diff = Date().timeIntervalSince(d)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60))分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600))小时前" }
        if isSameDay(d, Calendar.current.date(byAdding: .day, value: -1, to: Date())) { return "昨天" }
        return dayStamp(ms)
    }

    /// HH:mm
    static func clock(_ ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let f = DateFormatter()
        f.timeZone = cn
        f.dateFormat = "HH:mm"
        return f.string(from: date(ms))
    }

    /// M月d日 HH:mm
    static func full(_ ms: Int64) -> String {
        guard ms > 0 else { return "—" }
        let f = DateFormatter()
        f.timeZone = cn
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date(ms))
    }

    /// 今天 / 昨天 / M月d日（消息分组分隔条）
    static func dayLabel(_ ms: Int64) -> String {
        let d = date(ms)
        let cal = Calendar.current
        if isSameDay(d, Date()) { return "今天" }
        if isSameDay(d, cal.date(byAdding: .day, value: -1, to: Date())) { return "昨天" }
        let f = DateFormatter()
        f.timeZone = cn
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    /// MM-DD
    static func dayStamp(_ ms: Int64) -> String {
        let f = DateFormatter()
        f.timeZone = cn
        f.dateFormat = "MM-dd"
        return f.string(from: date(ms))
    }

    /// 剩余时长：H时MM分 / M分SS秒 / S秒（对齐网页 fmtLeft）
    static func fmtLeft(_ ms: Int64) -> String {
        let s = max(0, ms / 1000)
        if s >= 3600 { return "\(s / 3600)时\((s % 3600) / 60)分" }
        if s >= 60 { return "\(s / 60)分\(s % 60)秒" }
        return "\(s)秒"
    }

    static func isSameDay(_ a: Date, _ b: Date?) -> Bool {
        guard let b else { return false }
        var cal = Calendar.current
        cal.timeZone = cn
        return cal.isDate(a, inSameDayAs: b)
    }
}

// MARK: - 首字头像（演示页 cust-avatar 同款：纸面 + 墨字）

struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Strat.corner)
                .fill(Color.wxCell)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
            Text(String(name.first ?? "客"))
                .font(Strat.mono(size * 0.42, weight: .heavy))
                .foregroundColor(Color.wxText)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 未读徽标

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accent))
    }
}

// MARK: - 状态徽标（待确定/已确定/待修改/在线状态类）

enum WBStateKind { case good, warn, bad, muted }

struct StateChip: View {
    let text: String
    var kind: WBStateKind = .muted

    var color: Color {
        switch kind {
        case .good: return .statusOnline
        case .warn: return .wxWarn
        case .bad: return .wxDanger
        case .muted: return .wxSecondaryText
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                .strokeBorder(color.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - 在线状态文案（对齐网页 presenceText）

func presenceText(online: Bool, onlineAt: Int64, lastSeenAt: Int64) -> String {
    if online { return "在线 \(WBTime.clock(onlineAt))" }
    guard lastSeenAt > 0 else { return "离线" }
    let diff = Date().timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(lastSeenAt) / 1000))
    if diff < 60 { return "离线 刚刚" }
    if diff < 3600 { return "离线 \(Int(diff / 60))分钟前" }
    if diff < 86400 { return "离线 \(Int(diff / 3600))小时前" }
    return "离线 \(WBTime.rel(lastSeenAt))"
}

// MARK: - 墨线输入行（图纸风表单）

struct InkField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundColor(Color.wxSecondaryText)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundColor(Color.wxText)
                .disabled(disabled)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.wxFieldBackground)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
        }
    }
}

// MARK: - 统计片（码池 stats chip）

struct StatChipView: View {
    let title: String
    let value: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Strat.mono(17, weight: .heavy).monospacedDigit())
                .foregroundColor(highlight ? Color.accent : Color.wxText)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Color.wxSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.wxCell)
        .cornerRadius(Strat.corner)
        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
            .strokeBorder(Color.inkLine, lineWidth: 1))
    }
}

// MARK: - 抽屉容器（右滑资料/设置抽屉的统一纸面容器）

struct DrawerSheet<Content: View>: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .background(Color.wxBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - 墨行按钮（抽屉里的行级操作）

struct InkRowButton: View {
    let title: String
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(danger ? Color.wxDanger : Color.wxText)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
