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
