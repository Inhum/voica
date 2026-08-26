// Общая точка создания HTTP-клиентов (§9.5).
//
// Зачем не `URLSession.shared`: у неё НЕ БЫВАЕТ делегата — это свойство API, а не наша лень.
// Без делегата некому подставить учётные данные к прокси и некому отличить 407 от прочих
// сетевых бед. А все три сетевых обращения приложения — Groq (§2, §6.1), скачивание модели
// (§2.5) и проверка обновлений (§10) — обязаны ходить одинаково: иначе в корпоративной сети
// половина функций работает, половина нет, и разбираться в этом невозможно.
//
// ⚠️ Системный прокси используется БЕЗ всякого кода: и `URLSession`, и .NET читают системные
// настройки сами. Ломается не маршрутизация, а авторизация — прокси отвечает 407, учётных
// данных никто не шлёт. Поэтому здесь ровно две вещи: возможность ходить МИМО системного
// прокси (когда он прописан криво) и обработка вызова аутентификации.

import Foundation

enum HTTP {

    // MARK: - Сессии

    /// Общая сессия для обычных запросов (Groq, обновления).
    /// Пересоздаётся при смене настройки прокси: конфигурация читается один раз при создании.
    private(set) static var session: URLSession = makeSession()

    /// Конфигурация с учётом настройки «использовать системный прокси».
    ///
    /// Включено (по умолчанию) — ничего не трогаем: системные настройки и так применяются.
    /// Выключено — `connectionProxyDictionary = [:]` означает «идти напрямую», игнорируя
    /// системный прокси. Второе нужно не реже первого: криво прописанный в системе прокси
    /// мешает так же, как отсутствующий.
    static func configuration(_ base: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        if let p = explicitProxy() {
            base.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: p.host,
                kCFNetworkProxiesHTTPPort as String: p.port,
                "HTTPSEnable": 1, "HTTPSProxy": p.host, "HTTPSPort": p.port,
            ]
            return base
        }
        if !Prefs.useSystemProxy { base.connectionProxyDictionary = [:] }
        return base
    }

    /// Явно заданный прокси. Сейчас только dev-переопределение `$VOICA_PROXY=host:port`
    /// (как `$VOICA_GIGAAM` для модели) — нужно, чтобы прокси можно было проверить, не трогая
    /// системные настройки сети. Сюда же ляжет ручной прокси, если он появится (§9.5).
    static func explicitProxy() -> (host: String, port: Int)? {
        guard let raw = ProcessInfo.processInfo.environment["VOICA_PROXY"], !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        return (String(parts[0]), port)
    }

    private static func makeSession() -> URLSession {
        URLSession(configuration: configuration(), delegate: ProxyAuthDelegate.shared,
                   delegateQueue: nil)
    }

    /// Пересоздать общую сессию — звать после смены настройки прокси.
    /// Старая догоняет свои запросы и закрывается сама.
    static func reloadSession() {
        let old = session
        session = makeSession()
        old.finishTasksAndInvalidate()
    }

    // MARK: - Аутентификация на прокси

    /// Общий обработчик вызова аутентификации. Живёт здесь, а не в делегате, потому что
    /// делегатов два: общая сессия и загрузчик модели, у которого своя (ему нужен прогресс).
    ///
    /// Пароль в приложении НЕ спрашивается (§9.5). На macOS его хранит система — Системные
    /// настройки → Сеть → Прокси, оттуда он попадает в связку ключей. Наше дело — подставить
    /// то, что система уже знает, и не зациклиться, если не подошло.
    static func handleChallenge(_ challenge: URLAuthenticationChallenge,
                                completion: @escaping (URLSession.AuthChallengeDisposition,
                                                       URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.isProxy() else { return completion(.performDefaultHandling, nil) }
        NSLog("Voica: прокси \(space.host):\(space.port) требует авторизации (\(space.authenticationMethod))")

        // Повторный вызов по тому же запросу означает, что подставленное не подошло.
        // Пробовать снова нечем — иначе получится цикл вместо ошибки.
        guard challenge.previousFailureCount == 0 else {
            NSLog("Voica: прокси \(space.host):\(space.port) отклонил учётные данные")
            return completion(.cancelAuthenticationChallenge, nil)
        }
        if let cred = URLCredentialStorage.shared.defaultCredential(for: space) {
            NSLog("Voica: прокси \(space.host):\(space.port) — подставляю учётные данные из системы")
            return completion(.useCredential, cred)
        }
        // Своих учётных данных нет — пусть система применит то, что знает сама.
        completion(.performDefaultHandling, nil)
    }

    // MARK: - Диагностика

    /// Какой прокси система выбрала для этого адреса. Пишется в лог при сетевой неудаче:
    /// без этого разбор в чужой сети превращается в переписку (§9.5).
    static func proxyDescription(for url: URL) -> String {
        // ⚠️ Сначала СВОЙ прокси, потом системный. Проверка поймала: с заданным $VOICA_PROXY
        // строка писала «напрямую», потому что смотрела только в системные настройки. В логе
        // это худший вид вранья — уводит от причины, ради которой лог и заведён.
        if let explicit = explicitProxy() { return "\(explicit.host):\(explicit.port) (задан приложением)" }
        guard Prefs.useSystemProxy else { return "напрямую (системный прокси выключен в настройках)" }
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
              let list = CFNetworkCopyProxiesForURL(url as CFURL, settings)
                  .takeRetainedValue() as? [[String: Any]], !list.isEmpty else {
            return "не определён"
        }
        let described = list.map { entry -> String in
            let type = entry[kCFProxyTypeKey as String] as? String ?? "?"
            if type == (kCFProxyTypeNone as String) { return "напрямую" }
            let host = entry[kCFProxyHostNameKey as String] as? String ?? "?"
            let port = entry[kCFProxyPortNumberKey as String] as? Int
            return port.map { "\(type) \(host):\($0)" } ?? "\(type) \(host)"
        }
        return described.joined(separator: ", ")
    }

    /// Ошибка пришла от прокси? Тогда человеку надо сказать именно это, а не «сеть
    /// недоступна»: лечится это в настройках прокси, а не перезапуском.
    ///
    /// ⚠️ Домен здесь **kCFErrorDomainCFNetwork**, а не `NSURLErrorDomain` — проверено живым
    /// стендом: и недоступный прокси, и ответивший `407` дают код 310. Прежняя редакция
    /// смотрела только в `NSURLErrorDomain` и не ловила НИ ОДИН из двух случаев.
    ///
    /// ⚠️ Различить «требует пароль» и «не отвечает» для HTTPS нельзя в принципе: обмен идёт
    /// методом CONNECT внутри туннеля, и наружу оба исхода выходят одной ошибкой. Поэтому
    /// сообщение одно и годится для обоих — чинится и то и другое в одном месте.
    static func isProxyFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == kCFErrorDomainCFNetwork as String {
            return ns.code == Int(CFNetworkErrors.cfErrorHTTPSProxyConnectionFailure.rawValue)
                || ns.code == Int(CFNetworkErrors
                    .cfStreamErrorHTTPSProxyFailureUnexpectedResponseToCONNECTMethod.rawValue)
        }
        if ns.domain == NSURLErrorDomain { return ns.code == NSURLErrorUserAuthenticationRequired }
        return false
    }

    /// Человеческое сообщение о неудаче с прокси, с названным адресом.
    static func proxyFailureMessage(for url: URL) -> String {
        L("err.proxyFailed", proxyDescription(for: url))
    }

    /// HTTP-код 407 — тот же случай, но пришедший ответом, а не ошибкой.
    static let proxyAuthStatusCode = 407
}

/// Делегат общей сессии. Кроме прокси-аутентификации ему делать нечего.
final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = ProxyAuthDelegate()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                  URLCredential?) -> Void) {
        HTTP.handleChallenge(challenge, completion: completionHandler)
    }
}
