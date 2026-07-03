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

    /// Сброс всех настроек к значениям по умолчанию (для Delete all data).
    static func reset() {
        [Key.retentionDays, Key.storeAudio, Key.pttKeyCode, Key.dictationMode, Key.outputMode]
            .forEach { d.removeObject(forKey: $0) }
    }
}
