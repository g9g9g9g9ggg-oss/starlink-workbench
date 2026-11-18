import AVFoundation

/// 闪光灯桥：对齐安卓壳 StarlinkApp.torch(n) —— 系统闪光灯闪烁 n 次
enum TorchBlinker {

    static func blink(_ times: Int) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        let n = max(1, min(6, times))
        for i in 0..<(n * 2) {
            let on = i % 2 == 0
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = on ? .on : .off
                    device.unlockForConfiguration()
                } catch {
                    // 闪光灯被占用时静默跳过
                }
            }
        }
    }
}
