// Самотест без сети и GUI: ./build/Voica.app/Contents/MacOS/Voica --test-all
// Восстанавливает изменённое состояние (ключ, настройки, тестовую запись).

import Foundation

enum SelfTest {
    static func run() -> Bool {
        var passed = 0, failed = 0
        func check(_ name: String, _ cond: Bool) {
            if cond { passed += 1; print("  ✓ \(name)") }
            else { failed += 1; print("  ✗ \(name)") }
        }

        print("Voica self-test")

        // KeyStore — с восстановлением исходного ключа
        let savedKey = KeyStore.load()
        KeyStore.save("voica-selftest")
        check("keystore save/load", KeyStore.load() == "voica-selftest")
        if let s = savedKey { KeyStore.save(s) } else { KeyStore.delete() }
        check("keystore restored", KeyStore.load() == savedKey)

        // Store — вставка и удаление тестовой записи (история не меняется)
        let before = Store.shared.all().count
        if let id = Store.shared.insert(text: "__voica_selftest__", language: "ru",
                                        duration: 1.0, model: "test", audioTempURL: nil) {
            check("store insert", Store.shared.all().contains { $0.id == id })
            Store.shared.delete(id: id)
            check("store delete", !Store.shared.all().contains { $0.id == id })
        } else {
            check("store insert", false)
        }
        check("store count unchanged", Store.shared.all().count == before)

        // Store — стресс потокобезопасности: параллельные вставки и чтения с разных потоков.
        // Без серийной очереди это обращалось бы к одному соединению SQLite из многих потоков.
        let stressBefore = Store.shared.all().count
        let idsLock = NSLock()
        var stressIDs: [Int64] = []
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            if let id = Store.shared.insert(text: "__voica_stress__\(i)", language: nil,
                                            duration: nil, model: "stress", audioTempURL: nil) {
                idsLock.lock(); stressIDs.append(id); idsLock.unlock()
            }
            _ = Store.shared.all()   // чтение одновременно с чужими вставками
        }
        check("store concurrent inserts", stressIDs.count == 50)
        DispatchQueue.concurrentPerform(iterations: stressIDs.count) { i in
            Store.shared.delete(id: stressIDs[i])
        }
        check("store concurrent cleanup", Store.shared.all().count == stressBefore)

        // Prefs — round-trip с восстановлением
        let savedDays = Prefs.retentionDays
        Prefs.retentionDays = 7
        check("prefs round-trip", Prefs.retentionDays == 7)
        Prefs.retentionDays = savedDays

        let savedOutput = Prefs.outputMode
        Prefs.outputMode = "window"
        check("prefs outputMode round-trip", Prefs.outputMode == "window")
        Prefs.outputMode = savedOutput

        // Updater — сравнение версий и нормализация тега
        check("update isNewer patch", Updater.isNewer("0.4.1", than: "0.4.0"))
        check("update isNewer minor", Updater.isNewer("0.5.0", than: "0.4.9"))
        check("update not newer equal", !Updater.isNewer("0.4.0", than: "0.4.0"))
        check("update not newer older", !Updater.isNewer("0.3.9", than: "0.4.0"))
        check("update double-digit", Updater.isNewer("0.10.0", than: "0.9.0"))
        check("update normalize v-prefix", Updater.normalize("v0.5.0") == "0.5.0")

        // Локальный движок: CTC-декодер (чистая логика)
        let dec = CTCDecoder(pieces: ["<unk>", "▁при", "вет", "▁мир"])   // blank = 4
        check("ctc collapse+blank", dec.decode([1, 1, 4, 2, 4, 3, 3]) == "привет мир")
        check("ctc unk skipped", dec.decode([0, 1, 2]) == "привет")
        check("ctc empty", dec.decode([4, 4, 4]) == "")

        // Локальный движок: паритет мел-спектрограммы с Python (testdata/gigaam)
        let td = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("testdata/gigaam")
        let chirpWav = td.appendingPathComponent("chirp.wav")
        let chirpRef = td.appendingPathComponent("chirp-mel.f32")
        if FileManager.default.fileExists(atPath: chirpWav.path),
           let refData = try? Data(contentsOf: chirpRef),
           let sig = try? LocalSTT.loadWav16k(chirpWav) {
            let (mel, T) = MelFrontend.logMel(sig)
            let ref = refData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            if ref.count == mel.count {
                var maxDiff: Float = 0
                var maxIdx = 0
                for i in 0..<mel.count where abs(mel[i] - ref[i]) > maxDiff {
                    maxDiff = abs(mel[i] - ref[i]); maxIdx = i
                }
                let (m, t) = (maxIdx / T, maxIdx % T)
                print(String(format: "  · mel parity: %d кадров, max|Δ| = %.5f @ (mel %d, frame %d): наш %.4f, ref %.4f",
                             T, maxDiff, m, t, mel[maxIdx], ref[maxIdx]))
                check("mel parity vs torchaudio", maxDiff < 0.01)
            } else {
                print("  · mel parity: sig=\(sig.count) сэмплов, mel=\(mel.count), ref=\(ref.count)")
                check("mel parity vs torchaudio (размеры)", false)
            }
        } else {
            print("  · mel parity: testdata/gigaam не найдена — пропуск")
        }

        // Локальный движок e2e (только если модель и dev-эталон есть на машине)
        let devRef = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/gigaam/dev-ref")
        let refWav = devRef.appendingPathComponent("seg600.wav")
        if LocalSTT.isModelAvailable, FileManager.default.fileExists(atPath: refWav.path),
           let expected = try? String(contentsOf: devRef.appendingPathComponent("seg600-text.txt"),
                                      encoding: .utf8) {
            do {
                let sig = try LocalSTT.loadWav16k(refWav)
                let start = Date()
                let got = try LocalSTT.shared.transcribe(sig)
                print(String(format: "  · local e2e: %.1fs; текст: %@…", -start.timeIntervalSinceNow,
                             String(got.prefix(50))))
                check("local e2e text match", got == expected.trimmingCharacters(in: .whitespacesAndNewlines))
                if got != expected.trimmingCharacters(in: .whitespacesAndNewlines) {
                    print("    ожидалось: \(expected.prefix(80))")
                    print("    получено : \(got.prefix(80))")
                }
            } catch {
                check("local e2e text match", false)
                print("    ошибка: \(error.localizedDescription)")
            }
        } else {
            print("  · local e2e: модель/dev-ref не найдены — пропуск")
        }

        // Hotkey — сопоставление клавиш с флагами
        check("hotkey flag option", HotkeyManager.flag(for: 61) == .option)
        check("hotkey flag command", HotkeyManager.flag(for: 54) == .command)
        check("hotkey flag function", HotkeyManager.flag(for: 63) == .function)

        // Groq — конфигурация
        check("groq model", GroqClient.model == "whisper-large-v3-turbo")
        check("groq endpoint", GroqClient.endpoint.host == "api.groq.com")

        // Словарь терминов — подготовка prompt
        check("prompt empty → nil", GroqClient.promptField(from: "   \n ") == nil)
        check("prompt trims", GroqClient.promptField(from: "  Kubernetes, Groq  ") == "Kubernetes, Groq")
        let longVocab = String(repeating: "терм ", count: 500)   // ~2500 символов
        if let p = GroqClient.promptField(from: longVocab) {
            check("prompt truncated to budget", p.count <= GroqClient.promptCharBudget)
            // хвост — от уже обрезанной по пробелам строки (promptField сперва триммит)
            check("prompt keeps tail", longVocab.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(p))
        } else {
            check("prompt truncated to budget", false)
        }

        let savedVocab = Prefs.vocabulary
        Prefs.vocabulary = "test-term"
        check("prefs vocabulary round-trip", Prefs.vocabulary == "test-term")
        Prefs.vocabulary = savedVocab

        // LLM-постобработка — сборка промпта и настройка
        check("postprocess empty vocab → nil",
              GroqClient.postProcessPrompt(text: "привет", vocabulary: "  \n") == nil)
        if let p = GroqClient.postProcessPrompt(text: "тест кубер стил", vocabulary: "kubectl, Voica") {
            check("postprocess prompt has vocab", p.contains("kubectl, Voica"))
            check("postprocess prompt has text", p.contains("тест кубер стил"))
        } else {
            check("postprocess prompt has vocab", false)
        }
        check("postprocess model", GroqClient.postProcessModel == "llama-3.3-70b-versatile")

        let savedPP = Prefs.llmPostProcess
        Prefs.llmPostProcess = true
        check("prefs llmPostProcess round-trip", Prefs.llmPostProcess == true)
        Prefs.llmPostProcess = savedPP

        // Движок распознавания — настройка и загрузчик модели
        let savedEngine = Prefs.sttEngine
        check("prefs sttEngine default", UserDefaults.standard.string(forKey: "sttEngine") != nil
              || Prefs.sttEngine == "cloud")
        Prefs.sttEngine = "local"
        check("prefs sttEngine round-trip", Prefs.sttEngine == "local")
        Prefs.sttEngine = savedEngine

        check("model url is https github", ModelDownloader.downloadURL.scheme == "https"
              || ProcessInfo.processInfo.environment["VOICA_GIGAAM_URL"] != nil)
        check("model sha256 is set", ModelDownloader.expectedSHA256.count == 64)

        // sha256 — известный вектор ("abc")
        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("voica-selftest-\(UUID().uuidString)")
            try Data("abc".utf8).write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let h = try ModelDownloader.sha256Hex(of: tmp)
            check("sha256 known vector",
                  h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        } catch {
            check("sha256 known vector", false)
        }

        // распаковка zip (ditto) — round-trip на крошечной фикстуре
        do {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("voica-selftest-zip-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: base) }
            let srcDir = base.appendingPathComponent("payload.mlpackage", isDirectory: true)
            try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
            try Data("hello".utf8).write(to: srcDir.appendingPathComponent("f.txt"))
            let zip = base.appendingPathComponent("payload.zip")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--keepParent", srcDir.path, zip.path]
            try p.run(); p.waitUntilExit()
            let out = base.appendingPathComponent("out", isDirectory: true)
            try ModelDownloader.extract(zip: zip, to: out)
            let extracted = out.appendingPathComponent("payload.mlpackage/f.txt")
            check("model zip extract round-trip",
                  (try? String(contentsOf: extracted, encoding: .utf8)) == "hello")
        } catch {
            check("model zip extract round-trip", false)
        }

        print("Итог: \(passed) passed, \(failed) failed")
        return failed == 0
    }
}
