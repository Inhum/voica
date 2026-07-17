// Мел-спектрограмма для локального движка GigaAM — численный аналог их
// FeatureExtractor (torchaudio MelSpectrogram + log-clamp).
//
// Параметры зафиксированы конфигом модели v3_e2e_ctc (см. testdata/gigaam/meta.json):
//   16 кГц, hop 160, окно Ханна 320 (periodic), n_fft 320, center=false,
//   64 мела (HTK-шкала, 0–8000 Гц, без нормализации), power=2, затем log(clamp(1e-9,1e9)).
// Паритет с Python проверяется self-тестом на testdata/gigaam/chirp.wav.

import Accelerate
import Foundation

enum MelFrontend {
    static let sampleRate = 16_000
    static let nMels = 64
    static let hop = 160
    static let win = 320
    static let nFFT = 320
    static let nFreqs = nFFT / 2 + 1   // 161 (onesided)

    /// Число кадров для длины сигнала (center=false): floor((N-win)/hop)+1.
    static func frameCount(samples: Int) -> Int {
        samples < win ? 0 : (samples - win) / hop + 1
    }

    // Окно и мел-банк НЕ вычисляются по формулам, а загружаются из бандла —
    // это точные таблицы из чекпоинта модели (Resources/gigaam-window.f32,
    // gigaam-melfb.f32). Причина: в чекпоинте GigaAM сохранён СВОЙ мел-банк,
    // который перезаписывает стандартный torchaudio при загрузке весов и не
    // совпадает ни с одной стандартной формулой. Паритет — конструктивно.

    private static func loadF32(_ name: String, count: Int) -> [Float] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "f32"),
              let data = try? Data(contentsOf: url),
              data.count == count * MemoryLayout<Float>.size else {
            fatalError("Ресурс \(name).f32 отсутствует или неверного размера")
        }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Окно анализа (320) — из чекпоинта модели.
    private static let hann: [Float] = loadF32("gigaam-window", count: win)

    /// Мел-банк (161×64, row-major по частоте) — из чекпоинта модели.
    private static let filterbank: [Float] = loadF32("gigaam-melfb", count: nFreqs * nMels)

    /// DFT-сетап (комплексный, N=320 = 2^6·5 — поддерживается vDSP).
    /// Комплексный zop с нулевой мнимой частью — медленнее real-DFT, но без
    /// возни с упаковкой/масштабом vDSP; корректность важнее (паритет-тест).
    private static let dft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD)!

    /// Лог-мел спектрограмма. Возвращает массив [nMels * T] (mel-major: [m*T + t]) и T.
    static func logMel(_ signal: [Float]) -> (mel: [Float], frames: Int) {
        let T = frameCount(samples: signal.count)
        guard T > 0 else { return ([], 0) }

        // 1) power-спектр всех кадров → матрица P (T × 161)
        var power = [Float](repeating: 0, count: T * nFreqs)
        var inRe = [Float](repeating: 0, count: nFFT)
        var inIm = [Float](repeating: 0, count: nFFT)
        var outRe = [Float](repeating: 0, count: nFFT)
        var outIm = [Float](repeating: 0, count: nFFT)
        for t in 0..<T {
            let start = t * hop
            for i in 0..<win { inRe[i] = signal[start + i] * hann[i] }
            vDSP_DFT_Execute(dft, inRe, inIm, &outRe, &outIm)
            for f in 0..<nFreqs {
                power[t * nFreqs + f] = outRe[f] * outRe[f] + outIm[f] * outIm[f]
            }
        }

        // 2) P (T×161) × FB (161×64) → mel (T×64)
        var melTM = [Float](repeating: 0, count: T * nMels)
        vDSP_mmul(power, 1, filterbank, 1, &melTM, 1,
                  vDSP_Length(T), vDSP_Length(nMels), vDSP_Length(nFreqs))

        // 3) clamp(1e-9, 1e9) + ln, транспонирование в (64×T) как ждёт модель
        var lo: Float = 1e-9, hi: Float = 1e9
        vDSP_vclip(melTM, 1, &lo, &hi, &melTM, 1, vDSP_Length(T * nMels))
        var count = Int32(T * nMels)
        vvlogf(&melTM, melTM, &count)

        var mel = [Float](repeating: 0, count: nMels * T)
        for t in 0..<T {
            for m in 0..<nMels { mel[m * T + t] = melTM[t * nMels + m] }
        }
        return (mel, T)
    }
}
