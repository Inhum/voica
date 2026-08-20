// Запись микрофона в m4a (AAC, 16 кГц моно) — оптимально для Whisper и компактно.

import AVFoundation

final class Recorder: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    /// Захват умер посреди записи — устройство отвалилось, кодек упал, сессию прервали.
    /// Вызывается на главной очереди. Записанное ДО отказа остаётся валидным файлом.
    var onCaptureDied: ((String) -> Void)?

    private var watchdog: Timer?
    private var lastSeenTime: TimeInterval = 0
    private var stalledTicks = 0
    /// Столько секунд без прироста записанного времени считаем устройство мёртвым.
    /// Микрофон отдаёт данные и в полной тишине, поэтому пауза означает именно отказ,
    /// а не молчание говорящего.
    private static let stallSeconds = 3

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
            startWatchdog()
            return true
        } catch {
            NSLog("Voica: ошибка старта записи: \(error.localizedDescription)")
            return false
        }
    }

    /// Останавливает запись и возвращает файл и его длительность.
    func stop() -> (url: URL, duration: TimeInterval)? {
        stopWatchdog()
        guard let rec = recorder, let url = currentURL else { return nil }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        return (url, duration)
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    // MARK: - Сторож молчащего устройства

    /// Отказ микрофона посреди диктовки внешне неотличим от нормальной записи: состояние
    /// остаётся «идёт запись», плашка рисуется, а в файл ничего не пишется. Человек узнаёт
    /// об этом только в конце — по пустому или обрубленному тексту. На Windows такой отказ
    /// съел у пользователя шесть минут речи из шести с половиной.
    /// `currentTime` у `AVAudioRecorder` растёт, пока идёт запись, и замирает, когда захват
    /// умер, — этого достаточно, отдельный тап по буферам не нужен.
    private func startWatchdog() {
        lastSeenTime = 0
        stalledTicks = 0
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder else { return }
            let now = rec.currentTime
            if now > self.lastSeenTime {
                self.lastSeenTime = now
                self.stalledTicks = 0
                return
            }
            self.stalledTicks += 1
            if self.stalledTicks >= Self.stallSeconds { self.captureDied("остановился счётчик записи") }
        }
        RunLoop.main.add(t, forMode: .common)   // иначе замирает, пока открыто меню
        watchdog = t
    }

    private func stopWatchdog() { watchdog?.invalidate(); watchdog = nil }

    private func captureDied(_ reason: String) {
        guard recorder != nil else { return }
        stopWatchdog()
        NSLog("Voica: захват микрофона умер — \(reason)")
        onCaptureDied?(reason)
    }
}

extension Recorder: AVAudioRecorderDelegate {
    /// Кодек упал — причина от системы, единственная улика. Раньше молча терялась.
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        captureDied(error?.localizedDescription ?? "ошибка кодирования")
    }

    /// Запись завершилась сама, без нашего `stop()` — значит что-то её оборвало.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        captureDied("запись прервана системой")
    }
}
