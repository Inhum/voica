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
    static let model = "whisper-large-v3-turbo"

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

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(.network(err.localizedDescription))) }
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
    static let postProcessModel = "qwen/qwen3-32b"

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

    /// Исправляет искажённые термины из словаря через Groq LLM (qwen3-32b, без reasoning).
    /// Fail-open: при любой ошибке/таймауте возвращает исходный текст —
    /// диктовка никогда не блокируется постобработкой.
    static func postProcess(text: String, completion: @escaping (String) -> Void) {
        guard let key = currentAPIKey(),
              let prompt = postProcessPrompt(text: text, vocabulary: Prefs.vocabulary) else {
            return completion(text)
        }
        let payload: [String: Any] = [
            "model": postProcessModel,
            "temperature": 0,
            "reasoning_effort": "none",   // qwen3 — thinking-модель; размышления тут не нужны
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

        URLSession.shared.dataTask(with: req) { data, resp, err in
            guard err == nil,
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String else {
                return completion(text)   // fail-open
            }
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(cleaned.isEmpty ? text : cleaned)
        }.resume()
    }

    /// Проверка доступности chat-модели для ИИ-исправления: лёгкий запрос к
    /// chat completions. completion(nil) — модель доступна, иначе описание проблемы
    /// (403 — модель заблокирована в Groq-org, даём подсказку куда идти).
    static func validateChatModel(_ completion: @escaping (String?) -> Void) {
        guard let key = currentAPIKey() else { return completion(L("groq.err.noKey")) }
        let payload: [String: Any] = [
            "model": postProcessModel,
            "temperature": 0,
            "reasoning_effort": "none",
            "max_completion_tokens": 8,
            "messages": [["role": "user", "content": "ok"]],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return completion(L("groq.validate.noResponse"))
        }
        var req = URLRequest(url: chatEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err { return completion(err.localizedDescription) }
            guard let http = resp as? HTTPURLResponse else { return completion(L("groq.validate.noResponse")) }
            switch http.statusCode {
            case 200:  completion(nil)
            case 403:  completion(L("settings.vocab.llm.blocked", postProcessModel))
            case 401:  completion(L("groq.validate.rejected"))
            default:   completion(L("groq.validate.http", http.statusCode))
            }
        }.resume()
    }

    /// Проверка ключа через лёгкий GET /models. completion(nil) — ключ рабочий,
    /// иначе строка с описанием проблемы.
    static func validateKey(_ key: String, completion: @escaping (String?) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err { return completion(err.localizedDescription) }
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

        field("model", model)
        field("response_format", "verbose_json")   // даёт text + language + duration
        field("temperature", "0")
        // language не задаём — Whisper определяет сам (русский + английские вкрапления)
        if let prompt { field("prompt", prompt) }   // словарь терминов: подсказка написаний

        append("--\(boundary)--\r\n")
        return body
    }
}
