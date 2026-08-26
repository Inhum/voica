// Проверка обновлений через публичный GitHub Releases API.
// Репозиторий Voica публичный → запрос анонимный, без токена.
//
// Это ТОЛЬКО уведомление: если есть версия новее, приложение предлагает открыть
// страницу релиза. Скачивание и замену делает пользователь сам (см. ROADMAP —
// полноценный авто-апдейт через Sparkle отложен: он тянет фреймворк и требует
// нотаризации).

import Foundation

struct Update {
    let version: String     // без ведущего "v", напр. "0.5.0"
    let pageURL: URL        // html_url релиза на GitHub
}

enum Updater {
    static let releasesAPI = URL(string: "https://api.github.com/repos/Inhum/voica/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// completion(.success(update)) — доступна версия новее; .success(nil) — уже последняя.
    static func check(completion: @escaping (Result<Update?, Error>) -> Void) {
        var req = URLRequest(url: releasesAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Voica", forHTTPHeaderField: "User-Agent")   // GitHub API отклоняет запрос без User-Agent
        req.timeoutInterval = 20

        HTTP.session.dataTask(with: req) { data, resp, err in
            if let err = err {
                // Фоновая проверка ошибку не показывает (§10) — но в лог она обязана попасть,
                // иначе в закрытом контуре причина «обновления не проверяются» не находится.
                NSLog("Voica: проверка обновлений не удалась — \(err.localizedDescription), прокси: \(HTTP.proxyDescription(for: releasesAPI))")
                return completion(.failure(err))
            }
            guard let http = resp as? HTTPURLResponse, let data = data else {
                return completion(.failure(UpdateError.noResponse))
            }
            guard (200..<300).contains(http.statusCode) else {
                return completion(.failure(UpdateError.http(http.statusCode)))
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String,
                  let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else {
                return completion(.failure(UpdateError.decode))
            }
            let latest = normalize(tag)
            if isNewer(latest, than: normalize(currentVersion)) {
                completion(.success(Update(version: latest, pageURL: page)))
            } else {
                completion(.success(nil))
            }
        }.resume()
    }

    /// Убирает ведущие не-цифры из тега: "v0.5.0" → "0.5.0".
    static func normalize(_ tag: String) -> String {
        let s = tag.trimmingCharacters(in: .whitespaces)
        return String(s.drop(while: { !$0.isNumber }))
    }

    /// Сравнение версий покомпонентно (semver-подобно): 0.10.0 > 0.9.0.
    ///
    /// ⚠️ **Суффикс кандидата в релиз (`0.9.19-rc.1`) обязан отбрасываться перед разбором.**
    /// Без этого кусок `19-rc` не превращается в число, становится нулём, и у тестировщика
    /// кандидата приложение решает, что предыдущий выпуск новее, — то есть предлагает
    /// «обновиться» назад. Кандидаты показывают полную версию в About (§13), так что строка
    /// с суффиксом сюда приходит на каждой проверке обновлений.
    ///
    /// ⚠️ **Кандидат СТАРШЕ равного ему выпуска:** `0.9.19-rc.1` < `0.9.19`. Иначе тестировщик
    /// никогда не узнает, что вышел финал, — версии сравняются и обновление не предложится.
    /// Кандидаты между собой не упорядочиваем: в `/releases/latest` их нет по построению.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        // Числа равны — решает наличие суффикса: выпуск новее своего кандидата.
        return isPrerelease(current) && !isPrerelease(candidate)
    }

    /// Числовые части версии, без суффикса кандидата.
    static func numbers(_ version: String) -> [Int] {
        version.split(separator: "-")[0].split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isPrerelease(_ version: String) -> Bool { version.contains("-") }

    enum UpdateError: Error, LocalizedError {
        case noResponse, http(Int), decode
        var errorDescription: String? {
            switch self {
            case .noResponse:  return L("update.err.noResponse")
            case .http(let c): return L("update.err.http", c)
            case .decode:      return L("update.err.decode")
            }
        }
    }
}
