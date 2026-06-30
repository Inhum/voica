// Voica — диктовка с пунктуацией через Groq Whisper.
// Меню-бар приложение для macOS.
//
// Сборка:   ./scripts/build.sh      (собирает build/Voica.app)
// Запуск:   ./scripts/run.sh        (сборка + запуск с логами в терминал)
//
// Этап 2: рабочий цикл — PTT-хоткей / пункт меню → запись → Groq → текст в буфер + окно.

import Cocoa

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

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
    private lazy var aboutWindow = AboutWindowController()

    private var pulseTimer: Timer?
    private var state: DictationState = .idle { didSet { updateIcon() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Store.shared   // открыть БД и выполнить чистку аудио по retention

        NSApp.mainMenu = buildMainMenu()   // нужен Edit-меню, иначе не работают Cmd+V/C/X/A

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()
        updateIcon()

        // Окна Voica переводят приложение в обычный режим (видно в Cmd+Tab и Dock),
        // при закрытии последнего — обратно в фоновый меню-бар агент.
        NotificationCenter.default.addObserver(
            self, selector: #selector(voicaWindowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(voicaWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)

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

    // MARK: - Главное меню (для системных Cmd+V/C/X/A в полях ввода)

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: L("edit.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("edit.redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("edit.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("edit.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return mainMenu
    }

    // MARK: - Видимость окон / режим приложения

    @objc private func voicaWindowBecameKey(_ note: Notification) {
        guard (note.object as? NSWindow)?.identifier?.rawValue == "voica-main" else { return }
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    @objc private func voicaWindowWillClose(_ note: Notification) {
        let closing = note.object as? NSWindow
        guard closing?.identifier?.rawValue == "voica-main" else { return }
        DispatchQueue.main.async {
            let stillOpen = NSApp.windows.contains {
                $0.identifier?.rawValue == "voica-main" && $0.isVisible && $0 !== closing
            }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: - Меню

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        addItem(to: menu, title: L("menu.dictate"), action: #selector(toggleDictation), key: "")
        menu.addItem(.separator())
        addItem(to: menu, title: L("menu.history"), action: #selector(showHistory), key: "")
        addItem(to: menu, title: L("menu.settings"), action: #selector(showSettings), key: ",")
        addItem(to: menu, title: L("menu.about"), action: #selector(showAbout), key: "")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quit"),
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

        if state == .recording { startPulse() } else { stopPulse() }
    }

    private func startPulse() {
        guard pulseTimer == nil, let button = statusItem.button else { return }
        var dim = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                button.animator().alphaValue = dim ? 0.35 : 1.0
            }
            dim.toggle()
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        statusItem.button?.alphaValue = 1.0
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
                self.alert(L("alert.mic.title"), L("alert.mic.msg"))
                return
            }
            guard self.recorder.start() else {
                self.alert(L("alert.recstart.title"), L("alert.recstart.msg"))
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
                        self.alert(L("alert.empty.title"), L("alert.empty.msg"))
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
                    self.alert(L("alert.transcribe.title"), err.localizedDescription)
                }
            }
        }
    }

    // MARK: - Прочие пункты меню (заглушки до следующих этапов)

    @objc private func showHistory()  { historyWindow.reloadAndShow() }
    @objc private func showSettings() { settingsWindow.show() }

    @objc private func showAbout() { aboutWindow.show() }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }
}

// Режим самотеста — без GUI.
if CommandLine.arguments.contains("--test-all") {
    exit(SelfTest.run() ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // меню-бар агент, без иконки в доке
let delegate = AppDelegate()
app.delegate = delegate
app.run()
