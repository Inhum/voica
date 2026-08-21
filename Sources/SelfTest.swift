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

        // HistoryExporter — сериализация в MD / CSV / JSON (чистая, без файлов)
        let exRecs = [
            TranscriptRecord(id: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                             text: "Привет, мир", rawText: "привет мир",
                             language: "ru", durationSec: 2.5,
                             audioFilename: "a.m4a", model: "gigaam-v3-e2e-ctc"),
            TranscriptRecord(id: 2, createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                             text: "line with \"quote\", comma\nand newline", rawText: nil,
                             language: nil,
                             durationSec: nil, audioFilename: nil, model: "whisper-large-v3-turbo"),
        ]
        let exMd = HistoryExporter.serialize(exRecs, as: .markdown)
        check("export md has text", exMd.contains("Привет, мир"))
        check("export md has model", exMd.contains("gigaam-v3-e2e-ctc"))
        check("export md has heading", exMd.contains("## "))
        let exCsv = HistoryExporter.serialize(exRecs, as: .csv)
        check("export csv header", exCsv.contains("created_at,text,language,duration_sec,model"))
        check("export csv escapes quotes/commas/newlines",
              exCsv.contains("\"line with \"\"quote\"\", comma\nand newline\""))
        let exJson = HistoryExporter.serialize(exRecs, as: .json)
        if let data = exJson.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            check("export json count", arr.count == 2)
            check("export json text", (arr.first?["text"] as? String) == "Привет, мир")
            check("export json omits nil language", arr.last?["language"] == nil)
            check("export json has raw_text", (arr.first?["raw_text"] as? String) == "привет мир")
            check("export json omits nil raw_text", arr.last?["raw_text"] == nil)
        } else {
            check("export json parses", false)
        }
        check("export format ext",
              HistoryExporter.Format.markdown.ext == "md" && HistoryExporter.Format.json.ext == "json")

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

        // Store — удаление пачкой (мультивыделение в History): уходят ровно выбранные записи.
        let batchIDs = (0..<5).compactMap {
            Store.shared.insert(text: "__voica_batch__\($0)", language: nil,
                                duration: nil, model: "batch", audioTempURL: nil)
        }
        check("store batch insert", batchIDs.count == 5)
        Store.shared.delete(ids: Array(batchIDs.prefix(3)))
        let afterBatch = Store.shared.all().map(\.id)
        check("store batch delete removes picked", batchIDs.prefix(3).allSatisfy { !afterBatch.contains($0) })
        check("store batch delete keeps rest", batchIDs.suffix(2).allSatisfy { afterBatch.contains($0) })
        Store.shared.delete(ids: Array(batchIDs.suffix(2)))
        check("store batch delete cleanup", Store.shared.all().count == stressBefore)
        Store.shared.delete(ids: [])   // пустой список — не падаем и ничего не трогаем
        check("store batch delete empty is noop", Store.shared.all().count == stressBefore)

        // Сырой текст до ИИ-правки (§7): пара «raw → text» нужна, чтобы разбирать, кто наследил
        // в тексте — движок или модель. Дубль не храним: правка ничего не изменила → nil.
        if let rid = Store.shared.insert(text: "Привет, DeepSeek", language: nil, duration: nil,
                                         model: "test", audioTempURL: nil,
                                         rawText: "привет дипсик") {
            let rec = Store.shared.all().first { $0.id == rid }
            check("store raw text round-trip", rec?.rawText == "привет дипсик")
            check("store raw text keeps final", rec?.text == "Привет, DeepSeek")
            Store.shared.delete(id: rid)
        } else {
            check("store raw text round-trip", false)
        }
        if let nid = Store.shared.insert(text: "без правки", language: nil, duration: nil,
                                         model: "test", audioTempURL: nil) {
            check("store raw text nil when absent",
                  Store.shared.all().first { $0.id == nid }?.rawText == nil)
            Store.shared.delete(id: nid)
        } else {
            check("store raw text nil when absent", false)
        }

        // Prefs — round-trip с восстановлением
        let savedDays = Prefs.retentionDays
        Prefs.retentionDays = 7
        check("prefs round-trip", Prefs.retentionDays == 7)
        Prefs.retentionDays = savedDays

        let savedOutput = Prefs.outputMode
        Prefs.outputMode = "window"
        check("prefs outputMode round-trip", Prefs.outputMode == "window")
        Prefs.outputMode = savedOutput

        // Плашка записи и двойной тап — обе ВКЛючены по умолчанию (защита от случайного старта
        // и заметный индикатор), поэтому дефолт проверяем явно: тихая смена сломала бы UX.
        let savedHUD = Prefs.recordingHUD
        UserDefaults.standard.removeObject(forKey: "recordingHUD")
        check("prefs recordingHUD defaults on", Prefs.recordingHUD)
        Prefs.recordingHUD = false
        check("prefs recordingHUD round-trip", !Prefs.recordingHUD)
        Prefs.recordingHUD = savedHUD

        let savedTap = Prefs.toggleDoubleTap
        UserDefaults.standard.removeObject(forKey: "toggleDoubleTap")
        check("prefs toggleDoubleTap defaults on", Prefs.toggleDoubleTap)
        Prefs.toggleDoubleTap = false
        check("prefs toggleDoubleTap round-trip", !Prefs.toggleDoubleTap)
        Prefs.toggleDoubleTap = savedTap

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

        // Локальный движок: склейка кусков с нахлёстом (де-дуп слов на стыке)
        check("stitch overlap dedup", LocalSTT.stitch("привет мир как", "мир как дела") == "привет мир как дела")
        // Задвоение на стыке окон — оба случая взяты из настоящей длинной диктовки пользователя.
        // 1) Модель по-разному согласует одно и то же слово в соседних окнах.
        check("stitch dedup despite word ending",
              LocalSTT.stitch("руководителя одного отдела, руководителя другого отдела",
                              "одного отдела, руководитель другого отдела приходилось")
              == "руководителя одного отдела, руководителя другого отдела приходилось")
        // 2) Окно оборвало слово на полуслове: огрызок мешал сравнению и оставался в тексте.
        check("stitch drops cut-off tail word",
              LocalSTT.stitch("может быть из чего вообще строить из кип",
                              "может быть из чего вообще строить из кирпича")
              == "может быть из чего вообще строить из кирпича")
        // Терпимость не должна склеивать разные короткие слова.
        // Живой случай с Windows-стороны: окна разошлись в одном слове посреди ряда
        // («управляющий» / «управляющего» — 0.75 при пороге 0.8), и фраза уезжала дважды.
        check("stitch forgives one word in a long run",
              LocalSTT.stitch("сотруднику управляющий филиала сказал подожди",
                              "сотруднику управляющего филиала сказал подожди пока ничего")
              == "сотруднику управляющий филиала сказал подожди пока ничего")
        // Прощать последнее слово ряда нельзя: там обрубок, его роняет откат, а не прощение.
        check("stitch never forgives the last word of a run",
              LocalSTT.stitch("может быть из чего вообще строить из кип",
                              "может быть из чего вообще строить из кирпича")
              == "может быть из чего вообще строить из кирпича")
        // Короткий ряд прощения не получает — доказательств мало.
        check("stitch does not forgive in a short run",
              LocalSTT.stitch("раз стол", "стоп три") == "раз стол стоп три")
        // Окна разбили одно место на РАЗНОЕ число слов: «3кар» против «Три кар». Пословное
        // сравнение тут бессильно — выравнивание ломается, — выручает сравнение склеек.
        check("stitch dedups across word-count mismatch",
              LocalSTT.stitch("банковской системы 3кар. В 2004 году.",
                              "Три кар. В 2004 году защитил диплом на отлично.")
              == "банковской системы 3кар. В 2004 году. защитил диплом на отлично.")
        // Запасной путь не должен склеивать несвязанные фразы.
        check("stitch fuzzy keeps unrelated text",
              LocalSTT.stitch("сегодня хорошая погода на улице",
                              "завтра поеду в магазин за продуктами")
              == "сегодня хорошая погода на улице завтра поеду в магазин за продуктами")
        check("stitch keeps different short words",
              LocalSTT.stitch("я купил стол", "стоп машина") == "я купил стол стоп машина")
        check("stitch no overlap concatenates",
              LocalSTT.stitch("раз два", "три четыре") == "раз два три четыре")
        check("words similar on ending", LocalSTT.wordsSimilar("руководителя", "руководитель"))
        check("words similar rejects short lookalikes", !LocalSTT.wordsSimilar("стол", "стоп"))
        check("words similar rejects different", !LocalSTT.wordsSimilar("кирпича", "газоблока"))
        check("stitch no overlap", LocalSTT.stitch("раз два", "три четыре") == "раз два три четыре")
        check("stitch case+punct", LocalSTT.stitch("развернул Kubernetes через", "Через kubectl.") == "развернул Kubernetes через kubectl.")
        check("stitch empty", LocalSTT.stitch("", "текст") == "текст" && LocalSTT.stitch("текст", "") == "текст")

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

        // Локальный движок e2e (только если модель и эталон есть на машине).
        // Эталон живёт в репозитории — тест идёт на любой машине, а не только там, где
        // когда-то поднимали python-окружение. Старый путь в кэше оставлен фолбэком.
        let repoRef = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("testdata/gigaam-e2e")
        let cacheRef = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/gigaam/dev-ref")
        let devRef = FileManager.default.fileExists(
            atPath: repoRef.appendingPathComponent("seg600.wav").path) ? repoRef : cacheRef
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
        check("groq stt default", GroqClient.defaultSTTModel == "whisper-large-v3-turbo")
        check("groq stt models list", GroqClient.sttModels.contains("whisper-large-v3"))
        check("groq endpoint", GroqClient.endpoint.host == "api.groq.com")

        // Выбор STT-модели и языка (облако): дефолты, round-trip, отбраковка мусора
        let savedSTT = UserDefaults.standard.string(forKey: "sttModel")
        let savedLang = UserDefaults.standard.string(forKey: "sttLanguage")
        UserDefaults.standard.removeObject(forKey: "sttModel")
        check("sttModel default turbo", Prefs.sttModel == "whisper-large-v3-turbo")
        Prefs.sttModel = "whisper-large-v3"
        check("sttModel round-trip", Prefs.sttModel == "whisper-large-v3")
        Prefs.sttModel = "bogus-model"
        check("sttModel rejects unknown", Prefs.sttModel == "whisper-large-v3-turbo")
        check("sttLanguage default auto", (UserDefaults.standard.string(forKey: "sttLanguage") ?? "auto") == "auto" && Prefs.sttLanguage == "auto")
        Prefs.sttLanguage = "ru"
        check("sttLanguage round-trip", Prefs.sttLanguage == "ru")
        if let savedSTT { Prefs.sttModel = savedSTT } else { UserDefaults.standard.removeObject(forKey: "sttModel") }
        if let savedLang { Prefs.sttLanguage = savedLang } else { UserDefaults.standard.removeObject(forKey: "sttLanguage") }

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

        // Детерминированное исправление терминов (§6). Искажения ниже — НАСТОЯЩИЕ,
        // из истории пользователя: GigaAM пишет латиницу вперемешку с кириллицей.
        let vocab = "Claude Code, DeepSeek, Voica, focus-radio, Groq"

        // Корпус с живых диктовок (локальный движок, ИИ выключен) на РЕАЛЬНОМ словаре
        // пользователя. Отрицательные случаи важнее положительных: пропуск подберёт LLM,
        // а подменённое слово никто не заметит. Пороги вымерены именно на этих ловушках.
        let realVocab = "Claude Code, Cowork, ChatGPT, Voica, focus-radio, Groq, API, " +
                        "ЕИС, оферта, GigaAM, Tailscale, app-connector, exit-node, DeepSeek"
        func corpus(_ name: String, _ input: String, _ expected: String) {
            check("corpus: \(name)", Normalizer.fixTerms(input, vocabulary: realVocab) == expected)
        }
        // Чинится
        corpus("клодкод → Claude Code", "Проверка клодкод, проверка.", "Проверка Claude Code, проверка.")
        corpus("Tail scale → Tailscale", "Настрой Tail scale там.", "Настрой Tailscale там.")
        corpus("Up connector → app-connector", "Это Up connector.", "Это app-connector.")
        corpus("Fоcс радио → focus-radio", "Включи Fоcс радио.", "Включи focus-radio.")
        // ЛОВУШКИ — обычная русская речь, трогать нельзя ни в коем случае
        corpus("Вика ≠ Voica", "Вика прислала кода на 200 строк.", "Вика прислала кода на 200 строк.")
        corpus("Папа ≠ API, усы ≠ ЕИС", "Папа купил усы для костюма.", "Папа купил усы для костюма.")
        corpus("депеша ≠ DeepSeek", "Пришла депеша срочная.", "Пришла депеша срочная.")
        corpus("греческий ≠ Groq", "Я учил греческий, а не турецкий.", "Я учил греческий, а не турецкий.")
        corpus("Колодка ≠ Claude Code", "Колодка тормозная. Код заказа 105.", "Колодка тормозная. Код заказа 105.")
        // Грамматика: скелет «аферту» точно совпадает с «оферта», но подстановка дала бы
        // «Отправь оферта» — русские термины склоняются, это работа ИИ, а не правил.
        corpus("аферту не склоняем", "Отправь аферту.", "Отправь аферту.")
        // Известные промахи — движок услышал другое слово, скелет не спасёт. Фиксируем как есть,
        // чтобы заметить, если однажды начнут «чиниться» неправильно.
        corpus("плоткот не угадать", "Открой плоткот и запусти.", "Открой плоткот и запусти.")
        corpus("Войс не угадать", "Войс пишет с пунктуацией.", "Войс пишет с пунктуацией.")
        // Правильные термины проходят насквозь без изменений
        corpus("уже правильные", "Поставил DeepSeek, работаю в Cowork.", "Поставил DeepSeek, работаю в Cowork.")
        // Поймано полным прогоном по истории, придуманные ловушки это пропустили:
        // скелет «vice» совпадает с Voica (vk), близость ровно 0.60 — впритык проходила порог.
        corpus("vice versa ≠ Voica", "затем чат увидит результат и vice versa",
               "затем чат увидит результат и vice versa")
        check("normalizer fixes Dпсик",
              Normalizer.fixTerms("термином Dпсик в словаре", vocabulary: vocab)
              == "термином DeepSeek в словаре")
        check("normalizer fixes Dpсиcк",
              Normalizer.fixTerms("это Dpсиcк.", vocabulary: vocab) == "это DeepSeek.")
        check("normalizer fixes Deepsc",
              Normalizer.fixTerms("Deepsc, проверка", vocabulary: vocab) == "DeepSeek, проверка")
        check("normalizer keeps punctuation and spacing",
              Normalizer.fixTerms("а, Dпсик!  дальше", vocabulary: vocab) == "а, DeepSeek!  дальше")
        // Чистый русский и чистая латиница — не кандидаты: признак именно СМЕСЬ алфавитов.
        // «дипсик» — искорёженный DeepSeek кириллицей: скелет dpsk совпадает точно, четыре
        // буквы, термин латинский — чиним. Раньше правило видело только смешанный алфавит.
        check("normalizer fixes cyrillic term",
              Normalizer.fixTerms("дипсик и оферта", vocabulary: vocab) == "DeepSeek и оферта")
        check("normalizer ignores plain russian",
              Normalizer.fixTerms("сегодня оферта и работа", vocabulary: vocab)
              == "сегодня оферта и работа")
        check("normalizer ignores correct term",
              Normalizer.fixTerms("DeepSeek готов", vocabulary: vocab) == "DeepSeek готов")
        check("normalizer no vocabulary is noop",
              Normalizer.fixTerms("Dпсик", vocabulary: "  ") == "Dпсик")
        // Смешанное слово, не похожее ни на один термин, трогать нельзя.
        // Чистая латиница — тоже кандидат, но с побуквенной проверкой (≥ 0.5).
        // Живой промах: модель услышала «псих» вместо «сик», костяк разошёлся на одну согласную.
        check("normalizer fixes Dппсих",
              Normalizer.fixTerms("Поставил Dппсих, проверка", vocabulary: vocab)
              == "Поставил DeepSeek, проверка")
        // ⚠️ Кусок из одних пробелов: непустой, но слов в нём ноль. Без защиты запасной поиск
        // нахлёста уходил в `1...0` — в Swift это trap, падение приложения, а не исключение.
        check("stitch survives whitespace-only chunk",
              LocalSTT.stitch(" ", "проверка связи такая") == " проверка связи такая"
              || LocalSTT.stitch(" ", "проверка связи такая") == "проверка связи такая")
        check("stitch survives whitespace-only second chunk",
              !LocalSTT.stitch("проверка связи такая", " ").isEmpty)

        check("normalizer keeps lookalike latin word",
              Normalizer.fixTerms("это Greek текст", vocabulary: vocab) == "это Greek текст")
        // ⚠️ «Greek» держит НЕ порог, а костяк: `c` сворачивается в `k`, `q` — нет.
        // Спека до 0.9.18 называла причиной порог; проверяем ту, что работает на самом деле.
        check("skeleton separates Greek from Groq",
              Normalizer.skeleton("Greek") != Normalizer.skeleton("Groq"))
        check("similarity separates Deepsc from Greek",
              Normalizer.similarity("deepsc", "deepseek") >= 0.5
              && Normalizer.similarity("greek", "groq") < 0.5)
        // Порог 0.5, а не 0.6: живой промах — точный костяк при близости ровно 0.50.
        check("normalizer fixes Depsic at 0.50",
              Normalizer.fixTerms("Движок написал Depsic вместо", vocabulary: vocab)
              == "Движок написал DeepSeek вместо")
        check("normalizer leaves unknown mixed word",
              Normalizer.fixTerms("вот Xюйня тут", vocabulary: vocab) == "вот Xюйня тут")
        check("mixed script detected", Normalizer.hasMixedScript("Dпсик"))
        check("mixed script detected in tail", Normalizer.hasMixedScript("раadio"))
        check("mixed script not in plain words",
              !Normalizer.hasMixedScript("привет") && !Normalizer.hasMixedScript("DeepSeek"))
        check("skeleton matches across scripts",
              Normalizer.skeleton("Dпсик") == Normalizer.skeleton("DeepSeek")
              && Normalizer.skeleton("Deepsc") == Normalizer.skeleton("DeepSeek"))
        check("skeleton separates different terms",
              Normalizer.skeleton("Groq") != Normalizer.skeleton("DeepSeek"))

        // LLM-постобработка — сборка промпта и настройка
        check("postprocess empty vocab → nil",
              GroqClient.postProcessPrompt(text: "привет", vocabulary: "  \n") == nil)
        if let p = GroqClient.postProcessPrompt(text: "тест кубер стил", vocabulary: "kubectl, Voica") {
            check("postprocess prompt has vocab", p.contains("kubectl, Voica"))
            check("postprocess prompt has text", p.contains("тест кубер стил"))
        } else {
            check("postprocess prompt has vocab", false)
        }
        // Живые дефекты, пойманные проверкой пользователя 2026-08-21.
        // Движок пишет аббревиатуру строчными — её нельзя принимать за растянутый звук.
        check("filler keeps lowercase ии",
              Normalizer.stripFillers("Проверка ии. Сто процентов")
              == "Проверка ии. Сто процентов")
        // Точка после филлера принадлежит предложению, а не филлеру: иначе фразы слипаются.
        check("filler keeps sentence period",
              Normalizer.stripFillers("Проверка ммм. Сто процентов") == "Проверка. Сто процентов")
        // А запятая вокруг филлера дублируется — лишнюю убираем.
        check("filler drops duplicate comma",
              Normalizer.stripFillers("Ну, эээ, дальше") == "Ну, дальше")
        // Одиночное «э» — всегда мусор: союзом или предлогом оно, в отличие от «а», не бывает.
        check("filler removes bare э", Normalizer.stripFillers("Э это, короче") == "Это, короче")
        check("filler drops leading punctuation",
              Normalizer.stripFillers("-э-э. Проверка слов") == "Проверка слов")
        // Прямая кавычка, оставшаяся без пары после вычистки ёлочки.
        // Прямые кавычки становятся ёлочками по положению — и разнобой сам собой чинится:
        // движок открыл ёлочкой, закрыл прямой, теперь это нормальная пара.
        check("quotes fix mixed pair",
              Normalizer.balanceQuotes("он сказал: «Ну попробуй\".") == "он сказал: «Ну попробуй».")
        check("quotes convert straight to guillemets",
              Normalizer.balanceQuotes("он сказал \"да\" мне") == "он сказал «да» мне")
        // Живой случай: движок закрыл цитату после первого слова, хотя закавычена вся фраза.
        // Лишняя закрывающая — ПРЕЖДЕВРЕМЕННАЯ (за ней запятая и строчная), её и выбрасываем.
        check("quotes drop premature closing",
              Normalizer.balanceQuotes("Я сказал: «Да\", это стопроцентный вариант\".")
              == "Я сказал: «Да, это стопроцентный вариант».")
        // А настоящую закрывающую (за ней конец предложения) трогать нельзя — уходит последняя.
        check("quotes keep genuine closing",
              Normalizer.balanceQuotes("Он сказал «да». Потом ушёл».")
              == "Он сказал «да». Потом ушёл.")
        // В английском тексте прямые кавычки правильны — не трогаем.
        check("quotes keep english straight",
              Normalizer.balanceQuotes("he said \"yes\" to me") == "he said \"yes\" to me")
        // Пробел после двоеточия, забытый движком.
        check("quotes add space after colon",
              Normalizer.balanceQuotes("в ответ:\"Давай\".") == "в ответ: «Давай».")

        // Ещё два дефекта, пойманных прогоном по истории 2026-08-21.
        // «Эм» — не филлер: так движок пишет GigaAM.
        check("filler keeps Эм in a name",
              Normalizer.stripFillers("это \"Джига Эм\" такой") == "это \"Джига Эм\" такой")
        // Знак конца предложения стоит ДО филлера — его и надо сохранить, а слово после
        // филлера поднять в заглавную: филлер стоял в начале предложения.
        check("filler keeps question mark before",
              Normalizer.stripFillers("Почему? А-а, как бы") == "Почему? Как бы")
        check("filler keeps period before",
              Normalizer.stripFillers("ставил. Хмм, внедряли") == "ставил. Внедряли")

        // Непарные кавычки (§6.4). Живой случай: GigaAM открыла ёлочку и не закрыла.
        check("quotes drop unclosed opening",
              Normalizer.balanceQuotes("с термином «DeepSeek в словаре.")
              == "с термином DeepSeek в словаре.")
        check("quotes drop orphan closing",
              Normalizer.balanceQuotes("текст» хвост") == "текст хвост")
        check("quotes keep balanced pair",
              Normalizer.balanceQuotes("он сказал «подожди» и ушёл") == "он сказал «подожди» и ушёл")
        check("quotes keep two pairs",
              Normalizer.balanceQuotes("«раз» и «два»") == "«раз» и «два»")
        check("quotes untouched without any",
              Normalizer.balanceQuotes("обычный текст") == "обычный текст")

        // Филлеры (§6.2). Формы взяты из настоящих диктовок пользователя.
        // Филлер в начале предложения — следующее слово поднимаем в заглавную, иначе фраза
        // начинается со строчной и выглядит неряшливо.
        check("filler capitalises after leading drop",
              Normalizer.stripFillers("Э-э-э, проверка") == "Проверка")
        check("filler does not capitalise mid-sentence",
              Normalizer.stripFillers("это, ммм, проверка") == "это, проверка")
        // Живые случаи из истории: филлер СТРОЧНЫЙ, но стоит после точки — значит начинает
        // предложение, и следующее слово обязано быть с заглавной. Только регистра филлера
        // для этого мало, нужен уцелевший разделитель.
        check("filler capitalises after lowercase filler at sentence start",
              Normalizer.stripFillers("возьмут на улицу. э-э, на работу потом")
              == "возьмут на улицу. На работу потом")
        check("filler capitalises after uppercase filler mid-text",
              Normalizer.stripFillers("пошёл увольняться. Э-э, но тогда")
              == "пошёл увольняться. Но тогда")
        check("filler capitalises after short sentence",
              Normalizer.stripFillers("и ушёл. Всё. Э-э-э, вот и всё")
              == "и ушёл. Всё. Вот и всё")
        // ⚠️ Контрпример к признаку «филлер был с заглавной»: в середине фразы он врёт —
        // движок пишет филлер с заглавной как отдельную реплику. Живая строка из истории.
        check("filler does not capitalise after comma despite uppercase filler",
              Normalizer.stripFillers("их закрыли, Хмм, потом решили заниматься")
              == "их закрыли, потом решили заниматься")
        // «Угу», «ага», «мхм» — согласие, а не мычание: их НЕ удаляем. Раньше они лежали
        // в списке филлеров и не срабатывали никогда (гейт на две буквы), теперь их там нет.
        check("filler keeps agreement words",
              Normalizer.stripFillers("Угу, ага, мхм") == "Угу, ага, мхм")
        check("filler removes хмм", Normalizer.stripFillers("проверка хмм всяких слов")
              == "проверка всяких слов")
        check("filler removes ммм", Normalizer.stripFillers("ммм ну ладно") == "ну ладно")
        check("filler removes А-а", Normalizer.stripFillers("А-а, как бы почему") == "Как бы почему")
        // Растянутое НАСТОЯЩЕЕ слово распрямляется, а не удаляется.
        check("filler straightens Ну-у-у", Normalizer.stripFillers("Ну-у-у, там я работал")
              == "Ну, там я работал")
        // Отрицательные — важнее положительных.
        check("filler keeps bare а", Normalizer.stripFillers("А я пошёл") == "А я пошёл")
        check("filler keeps prepositions", Normalizer.stripFillers("у меня и он") == "у меня и он")
        check("filler keeps millimetres", Normalizer.stripFillers("отступ 5 мм ровно")
              == "отступ 5 мм ровно")
        check("filler keeps doubled letters",
              Normalizer.stripFillers("коммуникации и коммерция") == "коммуникации и коммерция")
        check("filler keeps ordinary words", Normalizer.stripFillers("мама мыла раму")
              == "мама мыла раму")

        // Вычистка рассуждений reasoning-моделей (§6.1). Баг с qwen/qwen3.6-27b:
        // ход мысли приезжал в текст пользователя вместо диктовки.
        check("strip think block",
              GroqClient.stripReasoning("<think>рассуждаю</think>Привет") == "Привет")
        check("strip think multiline + case",
              GroqClient.stripReasoning("<THINK>\nстрока\nещё\n</think>\n\nПривет") == "Привет")
        check("strip think with attributes",
              GroqClient.stripReasoning("<think foo=\"1\">x</think>Привет") == "Привет")
        check("strip several think blocks",
              GroqClient.stripReasoning("<think>a</think>Привет<think>b</think> мир") == "Привет мир")
        check("strip unclosed think → empty (ответ обрезали по лимиту токенов)",
              GroqClient.stripReasoning("<think>рассуждаю и не закончил").isEmpty)
        check("strip keeps plain text intact",
              GroqClient.stripReasoning("  Привет, kubectl.  ") == "Привет, kubectl.")
        check("strip does not eat lookalike word",
              GroqClient.stripReasoning("я think вслух") == "я think вслух")

        // Динамический выбор chat-модели: фильтр, приоритет-цепочка, дефолты, миграция
        check("chat filter keeps llama", GroqClient.isChatModelID("llama-3.3-70b-versatile"))
        check("chat filter keeps gpt-oss", GroqClient.isChatModelID("openai/gpt-oss-120b"))
        check("chat filter drops whisper", !GroqClient.isChatModelID("whisper-large-v3-turbo"))
        check("chat filter drops tts", !GroqClient.isChatModelID("playai-tts"))
        check("chat filter drops guard", !GroqClient.isChatModelID("meta-llama/llama-guard-4-12b"))
        // compound — агентная система с роутингом, а не chat-модель
        check("chat filter drops compound", !GroqClient.isChatModelID("groq/compound"))
        check("chat filter drops compound-mini", !GroqClient.isChatModelID("groq/compound-mini"))
        // allam — арабоязычная: первая по алфавиту, а значит молчаливый запасной выбор
        check("chat filter drops allam", !GroqClient.isChatModelID("allam-2-7b"))
        // Страховка от коллизии подстрок: "allam" не должен цеплять meta-llama ("…a-llama…")
        check("chat filter keeps meta-llama",
              GroqClient.isChatModelID("meta-llama/llama-4-scout-17b-16e-instruct"))
        check("pick prefers chain",
              GroqClient.pickRecommended(from: ["llama-3.1-8b-instant", "openai/gpt-oss-120b"]) == "openai/gpt-oss-120b")
        // Снятая с раздачи модель не должна выигрывать у живой, даже если провайдер её ещё отдаёт
        check("pick ignores retired head",
              GroqClient.pickRecommended(from: ["llama-3.3-70b-versatile", "openai/gpt-oss-20b"]) == "openai/gpt-oss-20b")
        check("pick falls back to first",
              GroqClient.pickRecommended(from: ["some-new-model"]) == "some-new-model")
        check("pick empty → nil", GroqClient.pickRecommended(from: []) == nil)

        let savedModel = UserDefaults.standard.string(forKey: "chatModel")
        let savedResolved = UserDefaults.standard.string(forKey: "resolvedChatModel")
        Prefs.chatModel = "auto"
        check("chatModel default auto", Prefs.chatModel == "auto")
        // Кэш резолва надо сбросить явно, иначе тест читает реальное состояние машины:
        // после ручного выбора модели в настройках там лежит она, а не сид, и проверка
        // падает на ровном месте. На CI настройки чистые, поэтому это не ловилось.
        UserDefaults.standard.removeObject(forKey: "resolvedChatModel")
        check("activeChatModel default seed",
              GroqClient.activeChatModel == GroqClient.defaultChatModel)
        Prefs.chatModel = "qwen/qwen3-32b"   // снятая с раздачи → миграция на auto
        check("retired chat model migrates to auto", Prefs.chatModel == "auto")
        Prefs.chatModel = "llama-3.3-70b-versatile"   // снята Groq 16.08.2026
        check("llama-3.3 migrates to auto", Prefs.chatModel == "auto")
        Prefs.chatModel = "llama-3.1-8b-instant"
        check("manual chatModel round-trip", Prefs.chatModel == "llama-3.1-8b-instant")
        check("activeChatModel honors manual", GroqClient.activeChatModel == "llama-3.1-8b-instant")
        if let savedModel { Prefs.chatModel = savedModel } else { UserDefaults.standard.removeObject(forKey: "chatModel") }
        if let savedResolved { Prefs.resolvedChatModel = savedResolved } else { UserDefaults.standard.removeObject(forKey: "resolvedChatModel") }

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
