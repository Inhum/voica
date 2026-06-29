// Voica — диктовка с пунктуацией через Groq Whisper.
// Меню-бар приложение для macOS.
//
// Сборка:   ./scripts/build.sh      (собирает build/Voica.app)
// Запуск:   ./scripts/run.sh        (сборка + запуск с логами в терминал)
//
// Этап 1: каркас — иконка в меню-баре + меню. Остальное приходит в следующих этапах.

import Cocoa

let appVersion = "0.1.0"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Voica")
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        addItem(to: menu, title: "Dictate", action: #selector(dictate), key: "")
        menu.addItem(.separator())
        addItem(to: menu, title: "History…", action: #selector(showHistory), key: "")
        addItem(to: menu, title: "Settings…", action: #selector(showSettings), key: ",")
        addItem(to: menu, title: "About Voica", action: #selector(showAbout), key: "")
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Voica",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Заглушки (наполняются в этапах 2–5)

    @objc private func dictate()      { stub("Dictate") }
    @objc private func showHistory()  { stub("History") }
    @objc private func showSettings() { stub("Settings") }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Voica \(appVersion)"
        alert.informativeText = "Диктовка с пунктуацией через Groq Whisper."
        alert.runModal()
    }

    private func stub(_ name: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = "Скоро."
        alert.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // меню-бар агент, без иконки в доке
let delegate = AppDelegate()
app.delegate = delegate
app.run()
