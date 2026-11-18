import UIKit

/// 震动引擎：节奏数组与网页版 navigator.vibrate 完全一致（毫秒，奇数位为停顿）
enum HapticEngine {

    /// pattern 例：[350, 200, 350] = 震350ms → 停200ms → 震350ms
    static func vibrate(_ pattern: [Int]) {
        guard !pattern.isEmpty else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        var delay: TimeInterval = 0
        for (index, ms) in pattern.enumerated() {
            let isBeat = index % 2 == 0
            if isBeat {
                let intensity: Double = pattern.count == 1 ? 0.8 : 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    generator.impactOccurred(intensity: intensity)
                }
            }
            delay += TimeInterval(ms) / 1000
        }
    }
}
