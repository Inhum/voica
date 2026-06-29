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
            return "Не задан API-ключ Groq. Откройте Settings и вставьте ключ."
        case .readFile:
            return "Не удалось прочитать аудиофайл записи."
        case .network(let m):
            return "Ошибка сети: \(m)"
        case .http(let code, let msg):
            return "Groq вернул \(code): \(Self.shorten(msg))"
        case .decode:
            return "Не удалось разобрать ответ Groq."
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

    static func transcribe(fileURL: URL,
                           completion: @escaping (Result<Transcription, GroqError>) -> Void) {
        guard let key = currentAPIKey() else { return completion(.failure(.noKey)) }
        guard let audio = try? Data(contentsOf: fileURL) else { return completion(.failure(.readFile)) }

        let boundary = "voica-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body(boundary: boundary, audio: audio, filename: fileURL.lastPathComponent)
        req.timeoutInterval = 120

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(.network(err.localizedDescription))) }
            guard let http = resp as? HTTPURLResponse, let data = data else {
                return completion(.failure(.network("пустой ответ")))
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

    /// Проверка ключа через лёгкий GET /models. completion(nil) — ключ рабочий,
    /// иначе строка с описанием проблемы.
    static func validateKey(_ key: String, completion: @escaping (String?) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err { return completion(err.localizedDescription) }
            guard let http = resp as? HTTPURLResponse else { return completion("нет ответа") }
            switch http.statusCode {
            case 200:  completion(nil)
            case 401:  completion("ключ отклонён (401)")
            default:   completion("HTTP \(http.statusCode)")
            }
        }.resume()
    }

    private static func body(boundary: String, audio: Data, filename: String) -> Data {
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

        append("--\(boundary)--\r\n")
        return body
    }
}
