// Локальный STT-движок: GigaAM v3_e2e_ctc, сконвертированная в CoreML
// (см. docs/spikes/gigaam-coreml.md). Работает офлайн, на Neural Engine.
//
// Конвейер: wav 16кГц → чанки по 25с (паддинг нулями до окна) → MelFrontend
// → CoreML (features [1,64,2499], feature_lengths) → log_probs → CTCDecoder.
//
// Модель ищется: $VOICA_GIGAAM (dev-переопределение) или
// Application Support/com.ushakov.voica/models/gigaam_v3_e2e.mlpackage.
// .mlpackage компилируется в .mlmodelc один раз и кэшируется рядом.
//
// Загрузка ленивая: preload() зовём при старте записи — пока пользователь
// говорит, модель успевает подняться; unloadAfterIdle() возвращает ОЗУ.

import AVFoundation
import CoreML
import Foundation

final class LocalSTT {
    static let shared = LocalSTT()

    /// Имя движка для колонки model в истории.
    static let modelName = "gigaam-v3-e2e-ctc"

    static let windowSamples = 25 * MelFrontend.sampleRate          // 400_000
    static let windowFrames = MelFrontend.frameCount(samples: windowSamples) // 2499
    static let overlapSamples = 2 * MelFrontend.sampleRate          // 32_000 — нахлёст соседних окон

    private var model: MLModel?
    private let queue = DispatchQueue(label: "com.ushakov.voica.localstt")
    private var idleTimer: DispatchSourceTimer?

    // Флаг «модель в памяти» с отдельным замком: читать можно с главного потока, НЕ
    // блокируясь на очереди, которая в этот момент может грузить модель (30–60 с в
    // первый раз). Нужен UI, чтобы показать «готовлю модель…» только когда есть ожидание.
    private let stateLock = NSLock()
    private var _modelLoaded = false
    var isModelLoaded: Bool { stateLock.lock(); defer { stateLock.unlock() }; return _modelLoaded }
    private func setModelLoaded(_ v: Bool) { stateLock.lock(); _modelLoaded = v; stateLock.unlock() }

    enum STTError: Error, LocalizedError {
        case modelNotFound, vocabMissing, badOutput
        var errorDescription: String? {
            switch self {
            case .modelNotFound: return L("local.err.noModel")
            case .vocabMissing:  return L("local.err.noVocab")
            case .badOutput:     return L("local.err.badOutput")
            }
        }
    }

    // MARK: - Расположение и жизненный цикл модели

    /// Путь к модели (.mlpackage или уже скомпилированный .mlmodelc), если она есть.
    static func modelURL() -> URL? {
        if let dev = ProcessInfo.processInfo.environment["VOICA_GIGAAM"], !dev.isEmpty {
            let url = URL(fileURLWithPath: dev)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let dir = Store.appSupportDir().appendingPathComponent("models", isDirectory: true)
        for name in ["gigaam_v3_e2e.mlmodelc", "gigaam_v3_e2e.mlpackage"] {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static var isModelAvailable: Bool { modelURL() != nil }

    /// Начать загрузку модели в фоне (звать при старте записи).
    func preload() {
        queue.async { _ = try? self.loadedModel() }
    }

    /// Немедленно выгрузить модель из ОЗУ (например, после удаления с диска).
    func unload() {
        queue.async {
            self.idleTimer?.cancel()
            self.idleTimer = nil
            self.model = nil
            self.setModelLoaded(false)
        }
    }

    /// Выгрузить модель после простоя (по умолчанию 15 минут), вернуть ОЗУ.
    func scheduleIdleUnload(after seconds: TimeInterval = 15 * 60) {
        queue.async {
            self.idleTimer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + seconds)
            t.setEventHandler { [weak self] in self?.model = nil; self?.setModelLoaded(false) }
            t.resume()
            self.idleTimer = t
        }
    }

    private func loadedModel() throws -> MLModel {
        if let m = model { return m }
        guard let src = Self.modelURL() else { throw STTError.modelNotFound }

        var compiled = src
        if src.pathExtension == "mlpackage" {
            // компилируем один раз, кэшируем .mlmodelc рядом с моделями
            let cacheDir = Store.appSupportDir().appendingPathComponent("models", isDirectory: true)
            let cached = cacheDir.appendingPathComponent("gigaam_v3_e2e.mlmodelc")
            if !FileManager.default.fileExists(atPath: cached.path) {
                let tmp = try MLModel.compileModel(at: src)
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: cached)
                try FileManager.default.copyItem(at: tmp, to: cached)
            }
            compiled = cached
        }
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .all   // CPU+GPU+ANE — система выберет сама
        let m = try MLModel(contentsOf: compiled, configuration: cfg)
        model = m
        setModelLoaded(true)
        return m
    }

    // MARK: - Транскрипция

    /// Синхронно транскрибирует 16кГц-моно сигнал (зови не с главного потока).
    func transcribe(_ signal: [Float]) throws -> String {
        guard let decoder = CTCDecoder() else { throw STTError.vocabMissing }
        let m = try queue.sync { try loadedModel() }

        // Длинные записи чанкуем окнами по 25с с нахлёстом ~2с: на стыке дубль слов
        // убираем (stitch), иначе слово/пунктуация на границе куска терялись или двоились.
        let step = Self.windowSamples - Self.overlapSamples
        var result = ""
        var offset = 0
        while offset < signal.count {
            let end = min(offset + Self.windowSamples, signal.count)
            let chunk = Array(signal[offset ..< end])
            guard chunk.count >= MelFrontend.win else { break }
            let ids = try infer(model: m, chunk: chunk)
            let text = decoder.decode(ids)
            if !text.isEmpty { result = Self.stitch(result, text) }
            if end == signal.count { break }
            offset += step
        }
        return result
    }

    /// Склейка соседних кусков с убиранием дубля на стыке: ищем наибольшее совпадение
    /// «хвост слов A == начало слов B» (без учёта регистра/пунктуации) и отбрасываем дубль;
    /// если совпадения нет — обычное соединение через пробел (не хуже прежнего).
    static func stitch(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        let aw = a.split(separator: " ").map(String.init)
        let bw = b.split(separator: " ").map(String.init)
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let an = aw.map(norm), bn = bw.map(norm)
        let maxK = min(12, aw.count, bw.count)   // окно поиска нахлёста (~2с речи)
        var overlap = 0
        var k = maxK
        while k >= 1 {
            if Array(an.suffix(k)) == Array(bn.prefix(k)) { overlap = k; break }
            k -= 1
        }
        return (aw + bw.dropFirst(overlap)).joined(separator: " ")
    }

    private func infer(model: MLModel, chunk: [Float]) throws -> [Int] {
        // паддинг нулями до фиксированного окна (форма входа статическая)
        var padded = chunk
        if padded.count < Self.windowSamples {
            padded.append(contentsOf: [Float](repeating: 0, count: Self.windowSamples - padded.count))
        }
        let realFrames = MelFrontend.frameCount(samples: chunk.count)
        let (mel, T) = MelFrontend.logMel(padded)
        precondition(T == Self.windowFrames, "неожиданное число кадров: \(T)")

        let feats = try MLMultiArray(shape: [1, NSNumber(value: MelFrontend.nMels), NSNumber(value: T)],
                                     dataType: .float32)
        mel.withUnsafeBufferPointer { src in
            feats.dataPointer.assumingMemoryBound(to: Float.self)
                .update(from: src.baseAddress!, count: mel.count)
        }
        let lens = try MLMultiArray(shape: [1], dataType: .int32)
        lens[0] = NSNumber(value: Int32(realFrames))

        let out = try model.prediction(from: MLDictionaryFeatureProvider(
            dictionary: ["features": feats, "feature_lengths": lens]))

        // выходы ищем по форме: 3-мерный — логиты, остальное — enc_len
        var logits: MLMultiArray?
        var encLenArr: MLMultiArray?
        for name in out.featureNames {
            guard let arr = out.featureValue(for: name)?.multiArrayValue else { continue }
            if arr.shape.count == 3 { logits = arr } else { encLenArr = arr }
        }
        guard let lp = logits else { throw STTError.badOutput }

        let tOut = lp.shape[1].intValue          // (1, T', V)
        let V = lp.shape[2].intValue
        var validT = tOut
        if let e = encLenArr, e.count >= 1 { validT = min(tOut, e[0].intValue) }

        var ids = [Int](repeating: 0, count: validT)
        if lp.dataType == .float32 {
            let p = lp.dataPointer.assumingMemoryBound(to: Float.self)
            for t in 0..<validT {
                var best = 0; var bestV = -Float.infinity
                let row = t * V
                for v in 0..<V where p[row + v] > bestV { bestV = p[row + v]; best = v }
                ids[t] = best
            }
        } else {
            for t in 0..<validT {
                var best = 0; var bestV = -Double.infinity
                for v in 0..<V {
                    let val = lp[[0, NSNumber(value: t), NSNumber(value: v)]].doubleValue
                    if val > bestV { bestV = val; best = v }
                }
                ids[t] = best
            }
        }
        return ids
    }

    // MARK: - Помощник для тестов: чтение wav 16кГц моно

    static func loadWav16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        guard fmt.sampleRate == 16_000, fmt.channelCount == 1 else {
            throw STTError.badOutput
        }
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let n = Int(buf.frameLength)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: n))
    }
}
