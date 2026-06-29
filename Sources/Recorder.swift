// Запись микрофона в m4a (AAC, 16 кГц моно) — оптимально для Whisper и компактно.

import AVFoundation

final class Recorder: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    /// Запрашивает доступ к микрофону (диалог появляется один раз).
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { completion(ok) }
            }
        default:
            completion(false)
        }
    }

    @discardableResult
    func start() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voica-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            guard rec.record() else { return false }
            recorder = rec
            currentURL = url
            return true
        } catch {
            NSLog("Voica: ошибка старта записи: \(error.localizedDescription)")
            return false
        }
    }

    /// Останавливает запись и возвращает файл и его длительность.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let rec = recorder, let url = currentURL else { return nil }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        return (url, duration)
    }

    var isRecording: Bool { recorder?.isRecording ?? false }
}

extension Recorder: AVAudioRecorderDelegate {}
