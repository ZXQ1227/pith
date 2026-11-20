import AVFoundation
import Foundation
import PithCore

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func start() async throws {
        try Task.checkCancellation()
        guard recorder == nil else {
            throw PithError.recording("录音已经开始，请先结束当前录音。")
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let isAuthorized: Bool
        if status == .notDetermined {
            isAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            isAuthorized = status == .authorized
        }
        // A system permission prompt can outlive the session that requested it.
        try Task.checkCancellation()
        guard isAuthorized else {
            throw PithError.permissionDenied("请在系统设置中允许 Pith 使用麦克风后重试。")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pith-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            try Task.checkCancellation()
            guard newRecorder.prepareToRecord(), newRecorder.record() else {
                throw PithError.recording("无法启动麦克风录音，请检查输入设备和权限。")
            }
            if Task.isCancelled {
                newRecorder.stop()
                throw CancellationError()
            }
            recordingURL = url
            recorder = newRecorder
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Samples live input without a second audio capture session.
    func sample() -> (duration: TimeInterval, level: Double) {
        guard let recorder, recorder.isRecording else { return (0, 0) }
        recorder.updateMeters()
        let silenceFloor: Float = -60
        let decibels = recorder.averagePower(forChannel: 0)
        let level = Double(max(0, min(1, (decibels - silenceFloor) / -silenceFloor)))
        return (max(0, recorder.currentTime), level)
    }

    func stop() throws -> URL {
        guard let recorder, let recordingURL else {
            throw PithError.recording("当前没有正在进行的录音。")
        }
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
                try? FileManager.default.removeItem(at: recordingURL)
                throw PithError.recording("录音为空，请说话后再停止。")
            }
        } catch {
            try? FileManager.default.removeItem(at: recordingURL)
            throw error
        }
        return recordingURL
    }

    func cancel() {
        recorder?.stop()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recorder = nil
        recordingURL = nil
    }
}
