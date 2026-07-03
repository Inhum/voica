// Авто-вставка распознанного текста в активное приложение.
// Кладёт текст в буфер обмена и синтезирует Cmd+V, чтобы вставить его туда,
// где сейчас курсор (в стороннем приложении, которое было активно во время диктовки).
//
// Voica — фоновый меню-бар агент и не забирает фокус, поэтому в момент вставки
// активным остаётся приложение пользователя.
//
// Требует Accessibility — то же разрешение, что и глобальный хоткей: без него
// синтез нажатий клавиш в чужие приложения системой игнорируется.

import Cocoa
import Carbon.HIToolbox

enum AutoInsert {
    /// Вставляет текст в активное приложение. Текст также остаётся в буфере обмена —
    /// это фолбэк: если вставлять некуда (нет активного поля ввода), можно нажать Cmd+V вручную.
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Небольшая задержка: даём активному приложению устояться после того,
        // как отпущен хоткей, прежде чем синтезировать Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCommandV()
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
