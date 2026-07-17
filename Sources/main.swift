// Voica — диктовка с пунктуацией через Groq Whisper.
// Меню-бар приложение для macOS.
//
// Сборка:   ./scripts/build.sh      (собирает build/Voica.app)
// Запуск:   ./scripts/run.sh        (сборка + запуск с логами в терминал)
//
// Этап 2: рабочий цикл — PTT-хоткей / пункт меню → запись → Groq → текст в буфер + окно.

import Cocoa
import UserNotifications

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

    private var updateItem: NSMenuItem!
    private var isCheckingUpdate = false
    private var latestUpdate: Update?

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
        // Кроме случая, когда выбран локальный движок: там ключ не обязателен.
        if currentAPIKey() == nil && Prefs.sttEngine != "local" {
            settingsWindow.showAndFocusKey()
        }

        maybeCheckForUpdatesOnLaunch()
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
        updateItem = addItem(to: menu, title: L("menu.checkUpdates"),
                             action: #selector(checkForUpdatesClicked), key: "")
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
            // Локальный движок: поднимаем модель, пока пользователь говорит, —
            // к концу записи она уже в памяти.
            if Prefs.sttEngine == "local", LocalSTT.isModelAvailable {
                LocalSTT.shared.preload()
            }
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
        // Локальный движок — если он выбран и модель скачана. Пока модель качается,
        // работаем через облако (решение UX: переключение «вступает» после загрузки).
        if Prefs.sttEngine == "local", LocalSTT.isModelAvailable {
            transcribeLocally(rec: rec)
        } else {
            transcribeViaCloud(rec: rec)
        }
    }

    private func transcribeViaCloud(rec: (url: URL, duration: TimeInterval)) {
        GroqClient.transcribe(fileURL: rec.url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let t):
                    self.handleTranscribed(t, rec: rec, model: GroqClient.model)
                case .failure(let err):
                    // Сеть недоступна, а локальная модель есть на диске —
                    // распознаём офлайн и ненавязчиво предупреждаем.
                    if case .network = err, LocalSTT.isModelAvailable {
                        self.notifyLocalFallback()
                        self.transcribeLocally(rec: rec)
                    } else {
                        self.state = .idle
                        try? FileManager.default.removeItem(at: rec.url)
                        self.alert(L("alert.transcribe.title"), err.localizedDescription)
                    }
                }
            }
        }
    }

    private func transcribeLocally(rec: (url: URL, duration: TimeInterval)) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> Transcription in
                let signal = try LocalSTT.loadWav16k(rec.url)
                let text = try LocalSTT.shared.transcribe(signal)
                return Transcription(text: text, language: "ru", duration: rec.duration)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                LocalSTT.shared.scheduleIdleUnload()   // вернуть ОЗУ после простоя
                switch result {
                case .success(let t):
                    self.handleTranscribed(t, rec: rec, model: LocalSTT.modelName)
                case .failure(let err):
                    self.state = .idle
                    try? FileManager.default.removeItem(at: rec.url)
                    self.alert(L("alert.transcribe.title"), err.localizedDescription)
                }
            }
        }
    }

    /// Общий хвост обоих движков: пустой результат / ИИ-исправление / доставка.
    private func handleTranscribed(_ t: Transcription, rec: (url: URL, duration: TimeInterval),
                                   model: String) {
        if t.text.isEmpty {
            state = .idle
            try? FileManager.default.removeItem(at: rec.url)
            alert(L("alert.empty.title"), L("alert.empty.msg"))
        } else if Prefs.llmPostProcess {
            // Состояние остаётся .transcribing, пока LLM исправляет термины.
            // postProcess fail-open: при любой ошибке вернёт исходный текст.
            // Работает и после локального движка (нужен ключ Groq).
            GroqClient.postProcess(text: t.text) { [weak self] final in
                DispatchQueue.main.async {
                    self?.deliver(text: final, transcription: t, rec: rec, model: model)
                }
            }
        } else {
            deliver(text: t.text, transcription: t, rec: rec, model: model)
        }
    }

    /// Системное уведомление о переходе на локальную модель (без модальных окон,
    /// чтобы не мешать диктовке). Если уведомления запрещены — просто лог.
    private func notifyLocalFallback() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else {
                NSLog("Voica: нет связи с облаком — распознаю локальной моделью")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = L("notify.fallback.title")
            content.body = L("notify.fallback.body")
            center.add(UNNotificationRequest(identifier: "voica-local-fallback",
                                             content: content, trigger: nil))
        }
    }

    /// Финальная доставка результата: история + буфер/вставка или окно.
    private func deliver(text: String, transcription t: Transcription,
                         rec: (url: URL, duration: TimeInterval), model: String) {
        state = .idle
        Store.shared.insert(text: text, language: t.language,
                            duration: t.duration ?? rec.duration,
                            model: model, audioTempURL: rec.url)
        try? FileManager.default.removeItem(at: rec.url)  // подчистить, если аудио не сохранялось
        if Prefs.outputMode == "window" {
            resultWindow.show(Transcription(text: text, language: t.language, duration: t.duration))
        } else {
            AutoInsert.insert(text)   // по умолчанию: вставить в активное поле
        }
        historyWindow.refreshIfVisible()
    }

    // MARK: - Прочие пункты меню (заглушки до следующих этапов)

    @objc private func showHistory()  { historyWindow.reloadAndShow() }
    @objc private func showSettings() { settingsWindow.show() }

    @objc private func showAbout() { aboutWindow.show() }

    // MARK: - Обновления

    /// Клик по пункту меню: если апдейт уже найден — открыть страницу, иначе проверить.
    @objc private func checkForUpdatesClicked() {
        if let update = latestUpdate {
            NSWorkspace.shared.open(update.pageURL)
        } else {
            checkForUpdates(manual: true)
        }
    }

    /// Тихая проверка при запуске: не чаще раза в сутки, без алертов.
    private func maybeCheckForUpdatesOnLaunch() {
        guard Prefs.checkUpdatesOnLaunch else { return }
        if let last = Prefs.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        checkForUpdates(manual: false)
    }

    /// manual=true — ручная проверка: показывает статус и алерты.
    /// manual=false — фоновая: молча меняет пункт меню, если есть новая версия.
    private func checkForUpdates(manual: Bool) {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        if manual { updateItem.title = L("menu.checkUpdates.checking") }
        Prefs.lastUpdateCheck = Date()

        Updater.check { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCheckingUpdate = false
                switch result {
                case .success(let update?):
                    self.latestUpdate = update
                    self.updateItem.title = L("menu.update.available", update.version)
                    if manual { self.offerUpdate(update) }
                case .success(nil):
                    self.latestUpdate = nil
                    self.updateItem.title = L("menu.checkUpdates")
                    if manual { self.alert(L("update.uptodate.title"),
                                           L("update.uptodate.msg", Updater.currentVersion)) }
                case .failure(let err):
                    self.latestUpdate = nil
                    self.updateItem.title = L("menu.checkUpdates")
                    if manual { self.alert(L("update.error.title"), err.localizedDescription) }
                }
            }
        }
    }

    private func offerUpdate(_ update: Update) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("update.available.title", update.version)
        a.informativeText = L("update.available.msg", Updater.currentVersion, update.version)
        a.addButton(withTitle: L("update.available.download"))
        a.addButton(withTitle: L("common.later"))
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.pageURL)
        }
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

// Режим самотеста — без GUI.
if CommandLine.arguments.contains("--test-all") {
    exit(SelfTest.run() ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // меню-бар агент, без иконки в доке
let delegate = AppDelegate()
app.delegate = delegate
app.run()
