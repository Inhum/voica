// Клиент Groq Speech-to-Text (OpenAI-совместимый эндпоинт).
// Docs: https://console.groq.com/docs/speech-to-text

import Foundation

struct Transcription {
    let text: String
    let language: String?
    let duration: Double?
}

enum GroqError: Error, LocalizedError {
    case noKey
    case readFile
    case network(String)
    case http(Int, String)
    case decode

    var errorDescription: String? {
        switch self {
        case .noKey:
            return L("groq.err.noKey")
        case .readFile:
            return L("groq.err.readFile")
        case .network(let m):
            return L("groq.err.network", m)
        case .http(let code, let msg):
            switch code {
            case 401: return L("groq.err.http401")
            // 407 приходит НЕ от Groq, а от корпоративного прокси по дороге (§9.5).
            // Называть его «Groq вернул 407» — отправлять человека чинить не то.
            case HTTP.proxyAuthStatusCode: return HTTP.proxyFailureMessage(for: GroqClient.endpoint)
            case 413: return L("groq.err.http413")
            case 429: return L("groq.err.http429")
            default:  return L("groq.err.httpOther", code, Self.shorten(msg))
            }
        case .decode:
            return L("groq.err.decode")
        }
    }

    private static func shorten(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 200 ? String(t.prefix(200)) + "…" : t
    }
}

enum GroqClient {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    /// Облачные модели распознавания, предлагаемые в UI. Turbo — быстрее, Large v3 — точнее.
    /// (distil-* — только английский, для русскоязычного приложения не предлагаем.)
    static let sttModels = ["whisper-large-v3-turbo", "whisper-large-v3"]
    static let defaultSTTModel = "whisper-large-v3-turbo"

    /// Модель распознавания, которой шлём СЕЙЧАС (выбор пользователя). Пишется и в историю.
    static var sttModel: String { Prefs.sttModel }

    /// Бюджет символов для поля `prompt`. Whisper учитывает только последние ~224 токена
    /// промпта, поэтому длинный словарь режем, сохраняя ХВОСТ. ~800 симв ≈ этот лимит.
    static let promptCharBudget = 800

    /// Готовит значение `prompt` из пользовательского словаря: тримминг + обрезка по бюджету
    /// (оставляем хвост). nil — если словарь пустой (тогда поле в запрос не кладём).
    static func promptField(from vocabulary: String) -> String? {
        let trimmed = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count <= promptCharBudget ? trimmed : String(trimmed.suffix(promptCharBudget))
    }

    static func transcribe(fileURL: URL,
                           completion: @escaping (Result<Transcription, GroqError>) -> Void) {
        guard let key = currentAPIKey() else { return completion(.failure(.noKey)) }
        guard let audio = try? Data(contentsOf: fileURL) else { return completion(.failure(.readFile)) }

        let boundary = "voica-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body(boundary: boundary, audio: audio, filename: fileURL.lastPathComponent,
                            prompt: promptField(from: Prefs.vocabulary))
        req.timeoutInterval = 120

        HTTP.session.dataTask(with: req) { data, resp, err in
            if let err = err {
                // Прокси-аутентификация приезжает обычной сетевой ошибкой — распознаём её
                // и пишем в лог, какой прокси выбрала система (§9.5).
                NSLog("Voica: запрос к Groq не удался — \(err.localizedDescription), прокси: \(HTTP.proxyDescription(for: Self.endpoint))")
                let msg = HTTP.userMessage(err, url: Self.endpoint)
                return completion(.failure(.network(msg)))
            }
            guard let http = resp as? HTTPURLResponse, let data = data else {
                return completion(.failure(.network(L("groq.validate.noResponse"))))
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                return completion(.failure(.http(http.statusCode, msg)))
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else {
                return completion(.failure(.decode))
            }
            let result = Transcription(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                language: obj["language"] as? String,
                duration: obj["duration"] as? Double
            )
            completion(.success(result))
        }.resume()
    }

    // MARK: - LLM-постобработка (исправление терминов из словаря)

    static let chatEndpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    static let modelsEndpoint = URL(string: "https://api.groq.com/openai/v1/models")!

    /// Приоритет-цепочка авто-выбора: берём первую из этих моделей, что есть в живом списке.
    /// Если ни одной нет — берём первую доступную вообще (см. `pickRecommended`).
    /// Порядок — по убыванию размера/качества среди того, что Groq реально раздаёт.
    /// `llama-3.3-70b-versatile` убрана: Groq снимает её 16.08.2026 (сама же рекомендует
    /// gpt-oss-120b и qwen3.6-27b на замену). `gemma2-9b-it` убрана: её в живом списке уже нет.
    static let recommendedChatModels = [
        "openai/gpt-oss-120b",
        "qwen/qwen3.6-27b",
        "openai/gpt-oss-20b",
        "llama-3.1-8b-instant",
    ]

    /// Сид-дефолт до того, как получен живой список (первый запуск / офлайн).
    static let defaultChatModel = "openai/gpt-oss-120b"

    /// Вызывается, когда chat-модель отдала 403 (не разрешена в Groq-организации пользователя).
    /// Ставит AppDelegate; аргумент — id модели. Срабатывает не чаще раза на модель за сессию.
    static var onChatModelBlocked: ((String) -> Void)?
    private static var blockedNotified: String?

    /// Модель, которой реально шлём постобработку СЕЙЧАС: ручной выбор пользователя или,
    /// в режиме "auto", последняя резолвнутая из живого списка (кэш в Prefs).
    static var activeChatModel: String {
        let choice = Prefs.chatModel
        return choice == "auto" ? Prefs.resolvedChatModel : choice
    }

    /// Оставляем только chat-совместимые id. Denylist (а не allowlist): у Groq нет поля
    /// «это chat», зато новые chat-семейства появляются регулярно — исключаем заведомо
    /// не-chat (whisper/tts/orpheus/guard/embed/...), остальное считаем пригодным.
    /// `compound` — не модель, а агентная система Groq с собственным роутингом и инструментами:
    /// для одной короткой правки терминов это лишний слой, а роутит она в том числе на модели,
    /// которых у организации может не быть (→ 403 вместо ответа).
    static func isChatModelID(_ id: String) -> Bool {
        let lower = id.lowercased()
        // `allam` — арабоязычная модель. Отсекается не потому, что плоха, а потому, что список
        // сортируется по алфавиту, а `pickRecommended` в крайнем случае берёт первый элемент:
        // «allam-2-7b» оказывается первым в алфавите и молча становится запасным выбором для
        // исправления РУССКИХ терминов. Все пользователи сейчас русскоязычные; если придёт
        // запрос на арабский — вернём и подумаем, как выбирать по языку, а не по алфавиту.
        let deny = ["whisper", "tts", "orpheus", "guard", "embed", "moderation", "distil",
                    "compound", "allam"]
        return !deny.contains { lower.contains($0) }
    }

    /// Живой список chat-моделей ключом пользователя (`GET /v1/models` + фильтр).
    /// completion(nil) — не удалось получить (нет ключа/сети/не-2xx).
    static func fetchChatModels(completion: @escaping ([String]?) -> Void) {
        guard let key = currentAPIKey() else { return completion(nil) }
        var req = URLRequest(url: modelsEndpoint)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        HTTP.session.dataTask(with: req) { data, resp, err in
            guard err == nil,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["data"] as? [[String: Any]] else {
                return completion(nil)
            }
            let ids = arr.compactMap { $0["id"] as? String }
                .filter(isChatModelID)
                .sorted()
            completion(ids)
        }.resume()
    }

    /// Выбирает лучшую доступную по приоритет-цепочке; фолбэк — первая в (отсортированном) списке.
    static func pickRecommended(from live: [String]) -> String? {
        for m in recommendedChatModels where live.contains(m) { return m }
        return live.first
    }

    /// Фоновое само-исцеление: если активная модель пропала из живого списка (или мы в auto),
    /// пересчитать резолв и закэшировать. Дёргается при 404 во время диктовки — следующая
    /// диктовка уже пойдёт на живую модель, релиз не нужен.
    static func healChatModelInBackground() {
        fetchChatModels { live in
            guard let live = live, !live.isEmpty, let pick = pickRecommended(from: live) else { return }
            if Prefs.chatModel != "auto", !live.contains(Prefs.chatModel) {
                Prefs.chatModel = "auto"          // ручной выбор протух → возвращаем к авто
            }
            if Prefs.chatModel == "auto" {
                Prefs.resolvedChatModel = pick
            }
        }
    }

    /// Результат проверки/резолва chat-модели для UI настроек.
    enum ChatModelState {
        case available(String)   // модель доступна (показываем какую)
        case switched(String)    // выбранная исчезла — авто-переключились на эту
        case blocked(String)     // 403 — разрешить в Groq-org
        case unavailable         // у ключа нет ни одной подходящей chat-модели
        case error(String)       // сеть/ключ/прочее
    }

    /// Промпт для исправления терминов. nil — словарь пуст, постобработка не нужна.
    static func postProcessPrompt(text: String, vocabulary: String) -> String? {
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vocab.isEmpty else { return nil }
        return """
        Ты — корректор диктовки. Ниже словарь терминов пользователя и распознанный текст. \
        В тексте могут встречаться искажённые варианты этих терминов (речь распознавалась на слух). \
        Верни ТОЛЬКО исправленный текст: замени искажённые варианты на правильные написания из словаря, \
        согласуя с падежом и контекстом. Если под искажение подходят несколько терминов словаря — \
        выбирай наиболее близкий по ЗВУЧАНИЮ к тому, что записано (например, «кубер стил» звучит как \
        kubectl, а не Kubernetes). Если слово в тексте уже совпадает со словарным термином \
        (пусть и в другом регистре, например с заглавной буквы) — оно правильное: не трогай его \
        и не меняй его регистр. Больше ничего не меняй — ни слова, ни пунктуацию. \
        Если исправлять нечего — верни текст как есть.

        СЛОВАРЬ: \(vocab)

        ТЕКСТ: \(text)
        """
    }

    /// Убирает блок рассуждений reasoning-моделей из ответа.
    /// Такие модели пишут ход мысли прямо в `content` тегом `<think>…</think>`, и без вычистки
    /// он целиком уезжал в текст пользователя вместо диктовки. Ловится не гипотетически:
    /// `qwen/qwen3.6-27b` — второе звено нашей цепочки (§6.1), то есть любой, у кого
    /// заблокирована `openai/gpt-oss-120b`, попадал в это на каждой диктовке.
    /// Незакрытый тег означает, что ответ обрезали по `max_completion_tokens` посреди
    /// рассуждения — полезного текста дальше уже нет, режем до конца.
    static func stripReasoning(_ s: String) -> String {
        var out = s
        while let r = out.range(of: "<think[^>]*>[\\s\\S]*?</think>",
                                options: [.regularExpression, .caseInsensitive]) {
            out.removeSubrange(r)
        }
        if let r = out.range(of: "<think[^>]*>[\\s\\S]*",
                             options: [.regularExpression, .caseInsensitive]) {
            out.removeSubrange(r)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Исправляет искажённые термины из словаря через Groq LLM (`activeChatModel`).
    /// Fail-open: при любой ошибке/таймауте возвращает исходный текст —
    /// диктовка никогда не блокируется постобработкой. Если модель отдала 404 (Groq её
    /// убрал) — запускаем фоновое само-исцеление, чтобы следующая диктовка пошла на живую.
    static func postProcess(text: String, completion: @escaping (String) -> Void) {
        guard let key = currentAPIKey(),
              let prompt = postProcessPrompt(text: text, vocabulary: Prefs.vocabulary) else {
            return completion(text)
        }
        let payload: [String: Any] = [
            "model": activeChatModel,
            "temperature": 0,
            "max_completion_tokens": 4096,
            "messages": [["role": "user", "content": prompt]],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return completion(text)
        }
        var req = URLRequest(url: chatEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 20

        HTTP.session.dataTask(with: req) { data, resp, err in
            if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                healChatModelInBackground()   // модель убрали — чиним к следующей диктовке
            }
            // 403 — модель есть на платформе, но не разрешена организации пользователя.
            // Само-исцеление тут не помогает (модель жива, доступа нет), а молча терять
            // исправление терминов на каждой диктовке — худший вариант: человек не узнает,
            // что функция не работает. Сообщаем один раз на модель за сессию.
            if let http = resp as? HTTPURLResponse, http.statusCode == 403 {
                let model = payload["model"] as? String ?? ""
                if blockedNotified != model {
                    blockedNotified = model
                    DispatchQueue.main.async { onChatModelBlocked?(model) }
                }
            }
            guard err == nil,
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String else {
                return completion(text)   // fail-open
            }
            let cleaned = stripReasoning(content)
            // Страховка к fail-open: исправление терминов подменяет отдельные слова, поэтому
            // длина ответа не может радикально отличаться от исходной. Если модель всё-таки
            // наговорила лишнего (или после вычистки не осталось ничего) — берём исходный текст.
            guard !cleaned.isEmpty, cleaned.count <= text.count * 2 + 50 else {
                return completion(text)
            }
            completion(cleaned)
        }.resume()
    }

    /// Резолвит и проверяет chat-модель для ИИ-исправления, при необходимости само-исцеляясь.
    /// Порядок: тянем живой список → выбираем целевую (ручной выбор, если он ещё жив; иначе
    /// приоритет-цепочка) → кэшируем резолв → пробным запросом отличаем 200 от 403 (Groq-org).
    /// Если ручной выбор исчез — молча переключаем на "auto" и сообщаем `.switched`.
    /// Возвращает состояние И живой список (для наполнения поповера выбора в UI).
    static func verifyChatModel(_ completion: @escaping (ChatModelState, [String]?) -> Void) {
        guard currentAPIKey() != nil else { return completion(.error(L("groq.err.noKey")), nil) }
        fetchChatModels { live in
            guard let live = live else {
                // Список не получили (сеть/ключ) — пробуем текущую активную напрямую.
                return probeModel(activeChatModel) { completion($0, nil) }
            }
            guard !live.isEmpty else { return completion(.unavailable, live) }

            let choice = Prefs.chatModel
            let target: String
            var healed = false
            if choice != "auto", live.contains(choice) {
                target = choice
            } else if choice != "auto" {
                guard let pick = pickRecommended(from: live) else { return completion(.unavailable, live) }
                Prefs.chatModel = "auto"      // выбранная модель исчезла → авто
                target = pick
                healed = true
            } else {
                guard let pick = pickRecommended(from: live) else { return completion(.unavailable, live) }
                target = pick
            }
            Prefs.resolvedChatModel = target

            probeModel(target) { state in
                if case .available(let m) = state, healed { completion(.switched(m), live) }
                else { completion(state, live) }
            }
        }
    }

    /// Пробный лёгкий запрос к chat-модели: отличает 200 (доступна) от 403 (заблокирована
    /// в Groq-org) и 404 (модель уже убрали) — /models показывает наличие, но не org-доступ.
    private static func probeModel(_ model: String, _ completion: @escaping (ChatModelState) -> Void) {
        guard let key = currentAPIKey() else { return completion(.error(L("groq.err.noKey"))) }
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_completion_tokens": 8,
            "messages": [["role": "user", "content": "ok"]],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return completion(.error(L("groq.validate.noResponse")))
        }
        var req = URLRequest(url: chatEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        HTTP.session.dataTask(with: req) { _, resp, err in
            if let err = err { return completion(.error(HTTP.userMessage(err, url: chatEndpoint))) }
            guard let http = resp as? HTTPURLResponse else { return completion(.error(L("groq.validate.noResponse"))) }
            switch http.statusCode {
            case 200:  completion(.available(model))
            case 403:  completion(.blocked(model))
            case 404:  healChatModelInBackground(); completion(.unavailable)
            case 401:  completion(.error(L("groq.validate.rejected")))
            default:   completion(.error(L("groq.validate.http", http.statusCode)))
            }
        }.resume()
    }

    /// Проверка ключа через лёгкий GET /models. completion(nil) — ключ рабочий,
    /// иначе строка с описанием проблемы.
    static func validateKey(_ key: String, completion: @escaping (String?) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        HTTP.session.dataTask(with: req) { _, resp, err in
            if let err = err { return completion(HTTP.userMessage(err, url: modelsEndpoint)) }
            guard let http = resp as? HTTPURLResponse else { return completion(L("groq.validate.noResponse")) }
            switch http.statusCode {
            case 200:  completion(nil)
            case 401:  completion(L("groq.validate.rejected"))
            default:   completion(L("groq.validate.http", http.statusCode))
            }
        }.resume()
    }

    private static func body(boundary: String, audio: Data, filename: String, prompt: String?) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audio)
        append("\r\n")

        field("model", sttModel)
        field("response_format", "verbose_json")   // даёт text + language + duration
        field("temperature", "0")
        // Язык: "auto" — не задаём (Whisper определяет сам, русский + английские вкрапления);
        // иначе форсируем ISO-639-1 (помогает коротким фразам с ошибочным авто-детектом).
        let lang = Prefs.sttLanguage
        if lang != "auto" { field("language", lang) }
        if let prompt { field("prompt", prompt) }   // словарь терминов: подсказка написаний

        append("--\(boundary)--\r\n")
        return body
    }
}
