// Настройки приложения (UserDefaults). UI для них — на этапе 4.

import Foundation

enum Prefs {
    private static let d = UserDefaults.standard

    private enum Key {
        static let retentionDays = "retentionDays"
        static let storeAudio    = "storeAudio"
        static let pttKeyCode    = "pttKeyCode"
        static let dictationMode = "dictationMode"   // "ptt" | "toggle"
        static let outputMode    = "outputMode"      // "insert" | "window"
        static let checkUpdates  = "checkUpdatesOnLaunch"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let vocabulary    = "vocabulary"
        static let llmPostProcess = "llmPostProcess"
        static let sttEngine     = "sttEngine"       // "cloud" | "local"
    }

    /// Сколько дней хранить аудиозаписи. 0 = не удалять. По умолчанию 30.
    static var retentionDays: Int {
        get { d.object(forKey: Key.retentionDays) == nil ? 30 : d.integer(forKey: Key.retentionDays) }
        set { d.set(newValue, forKey: Key.retentionDays) }
    }

    /// Хранить ли аудио вообще. По умолчанию да.
    static var storeAudio: Bool {
        get { d.object(forKey: Key.storeAudio) == nil ? true : d.bool(forKey: Key.storeAudio) }
        set { d.set(newValue, forKey: Key.storeAudio) }
    }

    /// keyCode модификатора для PTT. По умолчанию правый Option (61).
    static var pttKeyCode: Int {
        get { d.object(forKey: Key.pttKeyCode) == nil ? 61 : d.integer(forKey: Key.pttKeyCode) }
        set { d.set(newValue, forKey: Key.pttKeyCode) }
    }

    /// Режим запуска диктовки. По умолчанию PTT.
    static var dictationMode: String {
        get { d.string(forKey: Key.dictationMode) ?? "ptt" }
        set { d.set(newValue, forKey: Key.dictationMode) }
    }

    /// Куда отправлять распознанный текст. По умолчанию — авто-вставка в активное поле.
    /// "window" — старое поведение: показать редактируемое окно результата.
    static var outputMode: String {
        get { d.string(forKey: Key.outputMode) ?? "insert" }
        set { d.set(newValue, forKey: Key.outputMode) }
    }

    /// Проверять ли обновления при запуске (анонимный запрос к GitHub). По умолчанию да.
    static var checkUpdatesOnLaunch: Bool {
        get { d.object(forKey: Key.checkUpdates) == nil ? true : d.bool(forKey: Key.checkUpdates) }
        set { d.set(newValue, forKey: Key.checkUpdates) }
    }

    /// Момент последней проверки обновлений (для троттлинга «раз в сутки»). nil — не проверяли.
    static var lastUpdateCheck: Date? {
        get { let t = d.double(forKey: Key.lastUpdateCheck); return t == 0 ? nil : Date(timeIntervalSince1970: t) }
        set { d.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.lastUpdateCheck) }
    }

    /// Словарь терминов: строка, которую пользователь заносит в настройках. Подставляется
    /// в поле `prompt` Whisper, чтобы реже коверкались названия/жаргон/англицизмы. По умолчанию пусто.
    static var vocabulary: String {
        get { d.string(forKey: Key.vocabulary) ?? "" }
        set { d.set(newValue, forKey: Key.vocabulary) }
    }

    /// Исправлять ли термины из словаря через Groq LLM после распознавания.
    /// По умолчанию выкл: добавляет ~1–2 с задержки и один запрос к chat-модели.
    static var llmPostProcess: Bool {
        get { d.bool(forKey: Key.llmPostProcess) }
        set { d.set(newValue, forKey: Key.llmPostProcess) }
    }

    /// Движок распознавания: "cloud" (Groq) или "local" (GigaAM, офлайн). По умолчанию облако.
    static var sttEngine: String {
        get { d.string(forKey: Key.sttEngine) ?? "cloud" }
        set { d.set(newValue, forKey: Key.sttEngine) }
    }

    /// Сброс всех настроек к значениям по умолчанию (для Delete all data).
    static func reset() {
        [Key.retentionDays, Key.storeAudio, Key.pttKeyCode, Key.dictationMode, Key.outputMode,
         Key.checkUpdates, Key.lastUpdateCheck, Key.vocabulary, Key.llmPostProcess, Key.sttEngine]
            .forEach { d.removeObject(forKey: $0) }
    }
}
