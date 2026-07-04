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

        // Hotkey — сопоставление клавиш с флагами
        check("hotkey flag option", HotkeyManager.flag(for: 61) == .option)
        check("hotkey flag command", HotkeyManager.flag(for: 54) == .command)
        check("hotkey flag function", HotkeyManager.flag(for: 63) == .function)

        // Groq — конфигурация
        check("groq model", GroqClient.model == "whisper-large-v3-turbo")
        check("groq endpoint", GroqClient.endpoint.host == "api.groq.com")

        print("Итог: \(passed) passed, \(failed) failed")
        return failed == 0
    }
}
