import AVFoundation
import Foundation

/// `AVCaptureSession` 那条探针的接收端：只数块数和峰值。
///
/// 🚨 单独一个类是因为**必须真的看到数据**才算成功 ——
///    `startRunning()` 不抛错不代表有采样进来，
///    「起来了」和「一直在出数据」是两件事，今天已经在这上面栽过。
final class AltAudioSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private(set) var blocks = 0
    private(set) var peak: Float = 0

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        blocks += 1
        guard let bb = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var len = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &len,
                                          dataPointerOut: &ptr) == noErr,
              let p = ptr, len >= 2 else { return }
        p.withMemoryRebound(to: Int16.self, capacity: len / 2) { s in
            for i in 0..<(len / 2) {
                let v = abs(Float(s[i]) / 32768)
                if v > peak { peak = v }
            }
        }
    }
}
