import SwiftUI

/// 启动连接页（STRATUM 图纸风）：三域名逐行探测（对齐桌面/安卓壳的启动探测，全败自动重试）
struct ConnectView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.wxBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer().frame(height: 44)
                BrandLogo(size: 92)
                VStack(spacing: 5) {
                    Text("星链工作台")
                        .font(Strat.mono(26, weight: .heavy))
                        .tracking(4)
                        .foregroundColor(Color.wxText)
                    Text("STARLINK MATRIX · iOS 原生版")
                        .font(Strat.mono(11, weight: .medium))
                        .tracking(3)
                        .foregroundColor(Color.wxSecondaryText)
                }

                VStack(spacing: 0) {
                    ForEach(model.probeRows) { row in
                        probeRow(row)
                    }
                }
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
                .padding(.horizontal, 40)

                if model.phase == .failed {
                    Text("全部入口均不可达，\(Int(Constants.autoRetrySeconds)) 秒后自动重试")
                        .font(.footnote)
                        .foregroundColor(Color.wxSecondaryText)
                    Button {
                        model.retryConnect()
                    } label: {
                        Text("重新连接")
                            .font(Strat.mono(15, weight: .semibold))
                            .tracking(4)
                            .foregroundColor(.white)
                            .frame(width: 172, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: Strat.corner)
                                    .fill(Color.inkSolid)
                            )
                    }
                } else {
                    ProgressView()
                        .tint(Color.stratumAccent)
                        .padding(.top, 4)
                    Text("正在接入现网工作台…")
                        .font(.caption)
                        .foregroundColor(Color.wxSecondaryText)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.light)   // 图纸风浅色状态栏文字
    }

    @ViewBuilder
    private func probeRow(_ row: ProbeRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .foregroundColor(Color.inkLine)
            Text(row.host.replacingOccurrences(of: "https://", with: ""))
                .font(Strat.mono(13, weight: .medium))
                .foregroundColor(Color.wxText)
            Spacer()
            switch row.state {
            case .pending:
                Image(systemName: "circle")
                    .foregroundColor(Color.wxTertiaryText)
            case .probing:
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            case .ok:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.statusOnline)
            case .fail:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Color.wxDanger)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
