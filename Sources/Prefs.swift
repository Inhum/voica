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
        static let chatModel     = "chatModel"       // "auto" | конкретный id из живого списка
        static let resolvedChatModel = "resolvedChatModel"  // кэш последней резолвнутой конкретной модели
        static let sttModel      = "sttModel"        // облачная модель распознавания (whisper-*)
        static let sttLanguage   = "sttLanguage"     // "auto" | ISO-639-1 (ru/en/…) — только облако
    }

    /// Модели chat-completions, которые Groq снял с раздачи (404). Сохранённый выбор такой
    /// модели считаем протухшим → откатываем на «auto», чтобы приложение подобрало живую.
    private static let retiredChatModels: Set<String> = ["qwen/qwen3-32b"]

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

    /// Выбор chat-модели для ИИ-исправления терминов. "auto" — приложение само берёт лучшую
    /// доступную из живого списка (`GET /v1/models`) по внутренней приоритет-цепочке; иначе —
    /// конкретный id, выбранный пользователем вручную. По умолчанию "auto".
    /// Миграция: сохранённая снятая с раздачи модель (напр. `qwen/qwen3-32b`) → "auto".
    static var chatModel: String {
        get {
            let v = d.string(forKey: Key.chatModel) ?? "auto"
            return retiredChatModels.contains(v) ? "auto" : v
        }
        set { d.set(newValue, forKey: Key.chatModel) }
    }

    /// Кэш последней резолвнутой конкретной модели (для режима "auto" и офлайн-старта).
    /// Обновляется при verify/само-исцелении. Сид — первая в приоритет-цепочке.
    static var resolvedChatModel: String {
        get {
            let v = d.string(forKey: Key.resolvedChatModel) ?? GroqClient.defaultChatModel
            return retiredChatModels.contains(v) ? GroqClient.defaultChatModel : v
        }
        set { d.set(newValue, forKey: Key.resolvedChatModel) }
    }

    /// Облачная модель распознавания (Groq Whisper). Только облако — локальный движок один
    /// (GigaAM). По умолчанию `whisper-large-v3-turbo` (быстрее). Валидные — `GroqClient.sttModels`.
    static var sttModel: String {
        get {
            let v = d.string(forKey: Key.sttModel) ?? GroqClient.defaultSTTModel
            return GroqClient.sttModels.contains(v) ? v : GroqClient.defaultSTTModel
        }
        set { d.set(newValue, forKey: Key.sttModel) }
    }

    /// Язык распознавания для облака: "auto" (Whisper определяет сам) или ISO-639-1 (ru/en).
    /// Форсирование помогает коротким фразам, где авто-детект ошибается. По умолчанию "auto".
    /// Локальный движок игнорирует (GigaAM — русский).
    static var sttLanguage: String {
        get { d.string(forKey: Key.sttLanguage) ?? "auto" }
        set { d.set(newValue, forKey: Key.sttLanguage) }
    }

    /// Сброс всех настроек к значениям по умолчанию (для Delete all data).
    static func reset() {
        [Key.retentionDays, Key.storeAudio, Key.pttKeyCode, Key.dictationMode, Key.outputMode,
         Key.checkUpdates, Key.lastUpdateCheck, Key.vocabulary, Key.llmPostProcess, Key.sttEngine,
         Key.chatModel, Key.resolvedChatModel, Key.sttModel, Key.sttLanguage]
            .forEach { d.removeObject(forKey: $0) }
    }
}
