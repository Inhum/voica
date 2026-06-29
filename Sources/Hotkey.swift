// Глобальный hotkey для диктовки.
//
// Этап 2: режим PTT (push-to-talk) — удержание модификатора. По умолчанию
// правый Option (keyCode 61): зажал — пишет, отпустил — отправляет.
// Toggle-режим и настройка клавиши придут на этапе 4.
//
// Глобальный мониторинг клавиатуры требует разрешения Accessibility
// (System Settings → Privacy & Security → Accessibility).

import Cocoa
import ApplicationServices

final class HotkeyManager {
    enum Mode { case ptt, toggle }

    var onStart:  (() -> Void)?   // PTT: нажали
    var onStop:   (() -> Void)?   // PTT: отпустили
    var onToggle: (() -> Void)?   // Toggle: одно нажатие переключает запись

    /// keyCode модификатора (по умолчанию правый Option = 61).
    var pttKeyCode: UInt16 = 61
    /// Режим запуска диктовки.
    var mode: Mode = .ptt

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in
            self?.handle(e)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in
            self?.handle(e)
            return e
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == pttKeyCode else { return }
        let pressed = event.modifierFlags.contains(Self.flag(for: pttKeyCode))
        switch mode {
        case .ptt:
            if pressed && !isDown {
                isDown = true
                onStart?()
            } else if !pressed && isDown {
                isDown = false
                onStop?()
            }
        case .toggle:
            // Реагируем на нажатие, отпускание игнорируем.
            if pressed && !isDown {
                isDown = true
                onToggle?()
            } else if !pressed {
                isDown = false
            }
        }
    }

    /// Сопоставление keyCode модификатора с флагом, чтобы понять «нажат/отпущен».
    static func flag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 54, 55: return .command   // правый / левый Command
        case 58, 61: return .option    // левый / правый Option
        case 56, 60: return .shift     // левый / правый Shift
        case 59, 62: return .control   // левый / правый Control
        case 63:     return .function  // fn / Globe
        default:     return .option
        }
    }

    // MARK: - Accessibility

    /// Проверяет (и при необходимости запрашивает) разрешение Accessibility.
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
