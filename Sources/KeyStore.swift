// Хранение API-ключа Groq в защищённом файле (0600) в Application Support.
// Под ad-hoc подписью это надёжнее Keychain: переживает пересборку и обновление
// приложения. На время разработки поддерживается переменная окружения GROQ_API_KEY.

import Foundation
import Security

enum KeyStore {
    private static var fileURL: URL {
        Store.appSupportDir().appendingPathComponent("credentials")
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        let dir = Store.appSupportDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try value.write(to: fileURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: fileURL.path)
            cleanupLegacyKeychain()
            return true
        } catch {
            NSLog("Voica: не удалось сохранить ключ: \(error.localizedDescription)")
            return false
        }
    }

    static func load() -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    @discardableResult
    static func delete() -> Bool {
        cleanupLegacyKeychain()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do { try FileManager.default.removeItem(at: fileURL); return true }
        catch { return false }
    }

    /// Удаляет устаревшую запись из Keychain (миграция со старого хранилища).
    private static func cleanupLegacyKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ushakov.voica",
            kSecAttrAccount as String: "groq-api-key",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Текущий ключ: файл имеет приоритет, иначе переменная окружения (для разработки).
func currentAPIKey() -> String? {
    if let k = KeyStore.load(), !k.isEmpty { return k }
    if let env = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !env.isEmpty { return env }
    return nil
}
