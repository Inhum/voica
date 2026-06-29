// Voica — диктовка с пунктуацией через Groq Whisper.
// Меню-бар приложение для macOS.
//
// Сборка:   ./scripts/build.sh      (собирает build/Voica.app)
// Запуск:   ./scripts/run.sh        (сборка + запуск с логами в терминал)
//
// Этап 2: рабочий цикл — PTT-хоткей / пункт меню → запись → Groq → текст в буфер + окно.

import Cocoa

let appVersion = "0.1.0"

enum DictationState {
    case idle, recording, transcribing
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let hotkey = HotkeyManager()
    private lazy var resultWindow = ResultWindowController()
    private lazy var historyWindow = HistoryWindowController()
    private lazy var settingsWindow: SettingsWindowController = {
        let w = SettingsWindowController()
        w.onHotkeySettingsChanged = { [weak self] in self?.applyHotkeySettings() }
        return w
    }()

    private var state: DictationState = .idle { didSet { updateIcon() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Store.shared   // открыть БД и выполнить чистку аудио по retention

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()
        updateIcon()

        // Хоткей. Требует Accessibility для глобального перехвата.
        HotkeyManager.ensureAccessibility(prompt: true)
        hotkey.onStart  = { [weak self] in self?.startDictation() }
        hotkey.onStop   = { [weak self] in self?.stopDictation() }
        hotkey.onToggle = { [weak self] in self?.toggleDictation() }
        applyHotkeySettings()
        hotkey.start()

        // Онбординг: если ключа нет — сразу открыть Settings.
        if currentAPIKey() == nil {
            settingsWindow.showAndFocusKey()
        }
    }

    private func applyHotkeySettings() {
        hotkey.pttKeyCode = UInt16(Prefs.pttKeyCode)
        hotkey.mode = (Prefs.dictationMode == "toggle") ? .toggle : .ptt
    }

    // MARK: - Меню

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        addItem(to: menu, title: "Dictate", action: #selector(toggleDictation), key: "")
        menu.addItem(.separator())
        addItem(to: menu, title: "History…", action: #selector(showHistory), key: "")
        addItem(to: menu, title: "Settings…", action: #selector(showSettings), key: ",")
        addItem(to: menu, title: "About Voica", action: #selector(showAbout), key: "")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Voica",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    // MARK: - Иконка состояния

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let (symbol, tint): (String, NSColor?) = {
            switch state {
            case .idle:         return ("mic", nil)
            case .recording:    return ("mic.fill", .systemRed)
            case .transcribing: return ("waveform", .systemBlue)
            }
        }()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Voica")
        button.image?.isTemplate = (tint == nil)
        button.contentTintColor = tint
    }

    // MARK: - Диктовка

    @objc private func toggleDictation() {
        switch state {
        case .idle:         startDictation()
        case .recording:    stopDictation()
        case .transcribing: break
        }
    }

    private func startDictation() {
        guard state == .idle else { return }
        recorder.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.alert("Нет доступа к микрофону",
                           "Разрешите доступ в System Settings → Privacy & Security → Microphone.")
                return
            }
            guard self.recorder.start() else {
                self.alert("Не удалось начать запись", "Проверьте микрофон и попробуйте снова.")
                return
            }
            self.state = .recording
        }
    }

    private func stopDictation() {
        guard state == .recording, let rec = recorder.stop() else { return }
        // Слишком короткая запись — вероятно случайное нажатие.
        guard rec.duration >= 0.3 else {
            try? FileManager.default.removeItem(at: rec.url)
            state = .idle
            return
        }
        state = .transcribing
        GroqClient.transcribe(fileURL: rec.url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = .idle
                switch result {
                case .success(let t):
                    if t.text.isEmpty {
                        try? FileManager.default.removeItem(at: rec.url)
                        self.alert("Пусто", "Whisper не распознал речь. Попробуйте ещё раз.")
                    } else {
                        Store.shared.insert(text: t.text, language: t.language,
                                            duration: t.duration ?? rec.duration,
                                            model: GroqClient.model, audioTempURL: rec.url)
                        try? FileManager.default.removeItem(at: rec.url)  // подчистить, если аудио не сохранялось
                        self.resultWindow.show(t)
                        self.historyWindow.refreshIfVisible()
                    }
                case .failure(let err):
                    try? FileManager.default.removeItem(at: rec.url)
                    self.alert("Ошибка транскрибации", err.localizedDescription)
                }
            }
        }
    }

    // MARK: - Прочие пункты меню (заглушки до следующих этапов)

    @objc private func showHistory()  { historyWindow.reloadAndShow() }
    @objc private func showSettings() { settingsWindow.show() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Voica \(appVersion)"
        alert.informativeText = "Диктовка с пунктуацией через Groq Whisper."
        alert.runModal()
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // меню-бар агент, без иконки в доке
let delegate = AppDelegate()
app.delegate = delegate
app.run()
