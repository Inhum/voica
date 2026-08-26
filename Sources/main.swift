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
    private let prepHUD = PrepHUD()
    private let recordingHUD = RecordingHUD()
    private var pulseTimer: Timer?
    private var lastIdleTapAt: Date?
    private var isShowingSetupAlert = false   // для «двойного тапа» в режиме Toggle

    private var state: DictationState = .idle { didSet { updateIcon() } }

    private var updateItem: NSMenuItem!
    private var isCheckingUpdate = false
    private var latestUpdate: Update?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GroqClient.onChatModelBlocked = { [weak self] model in self?.notifyChatModelBlocked(model) }

        _ = Store.shared   // открыть БД и выполнить чистку аудио по retention

        recorder.onCaptureDied = { [weak self] _ in self?.handleCaptureDied() }
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
        hotkey.onToggle = { [weak self] in self?.hotkeyToggle() }
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
        edit.addItem(.separator())
        // Cmd+F через пункт меню, а не через перехват в окне: меню получает событие первым,
        // и команда заодно становится видимой. Цель — явная, чтобы не зависеть от того,
        // где сейчас фокус (список, текст записи, поле поиска).
        let find = NSMenuItem(title: L("edit.find"), action: #selector(findInHistory), keyEquivalent: "f")
        find.target = self
        edit.addItem(find)

        return mainMenu
    }

    // MARK: - Видимость окон / режим приложения

    @objc private func voicaWindowBecameKey(_ note: Notification) {
        guard (note.object as? NSWindow)?.identifier?.rawValue == "voica-main" else { return }
        if NSApp.activationPolicy() != .regular {
            setActivationPolicy(.regular, why: "окно стало ключевым")
        }
    }

    /// Есть ли на экране хоть одно наше окно. От этого зависит, быть ли агентом.
    private func hasVisibleMainWindow() -> Bool {
        NSApp.windows.contains { $0.identifier?.rawValue == "voica-main" && $0.isVisible }
    }

    /// Смена режима приложения с записью в лог: место тонкое (порядок относительно активации
    /// решает, попадёт ли приложение в Cmd+Tab), и без следа в логе разбирать это нечем.
    private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy, why: String) {
        NSLog("Voica: режим приложения → \(policy == .regular ? "обычное" : "агент") (\(why))")
        NSApp.setActivationPolicy(policy)
    }

    @objc private func voicaWindowWillClose(_ note: Notification) {
        let closing = note.object as? NSWindow
        guard closing?.identifier?.rawValue == "voica-main" else { return }
        DispatchQueue.main.async {
            let stillOpen = NSApp.windows.contains {
                $0.identifier?.rawValue == "voica-main" && $0.isVisible && $0 !== closing
            }
            if !stillOpen { self.setActivationPolicy(.accessory, why: "последнее окно закрыто") }
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
            // При включённой плашке она — единственный индикатор Voica от старта записи до
            // готового текста: иконку в менюбаре не трогаем вовсе, чтобы не рябило двумя
            // сигналами сразу. Цветные состояния — только в режиме-фолбэке (плашка выключена):
            // красный микрофон пульсирует на записи, синяя волна горит на распознавании.
            case .recording:    return Prefs.recordingHUD ? ("mic", nil) : ("mic.fill", .systemRed)
            case .transcribing: return Prefs.recordingHUD ? ("mic", nil) : ("waveform", .systemBlue)
            }
        }()
        // Цвет иконки в менюбаре задаём ТОЛЬКО палитрой самого символа. contentTintColor тут
        // бесполезен в обе стороны: template-картинку менюбар всё равно перекрашивает под свою
        // тему, а не-template рисуется своими цветами и оттенок игнорирует — оба состояния
        // выходили монохромными. paletteColors красит символ на уровне изображения, и оно
        // приходит уже не-template (isTemplate = false), так что менюбар его не перебивает.
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Voica")
        if let tint {
            button.image = base?.withSymbolConfiguration(.init(paletteColors: [tint]))
        } else {
            button.image = base
            button.image?.isTemplate = true   // покой — обычная иконка под тему менюбара
        }
        button.contentTintColor = nil

        // Индикатор диктовки: по умолчанию — плавающая плашка снизу (её проще заметить, чем пульс
        // иконки, который путали с системной оранжевой точкой). Она же берёт на себя и стадию
        // распознавания. Если плашка выключена в настройках — работает старый путь через иконку
        // менюбара: пульс на записи, синяя волна на распознавании.
        switch state {
        case .recording:
            if Prefs.recordingHUD {
                stopPulse()
                recordingHUD.show(onCancel: { [weak self] in self?.cancelDictation() },
                                  onStop:   { [weak self] in self?.stopDictation() },
                                  level:    { [weak self] in self?.recorder.inputLevel ?? 0 })
            } else {
                recordingHUD.hide()
                startPulse()
            }
        case .transcribing:
            stopPulse()   // пульс — только про запись; распознавание показывается статикой
            if Prefs.recordingHUD { recordingHUD.showTranscribing() } else { recordingHUD.hide() }
        case .idle:
            recordingHUD.hide()
            stopPulse()
        }
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

    /// Пункт меню «Dictate» — прямое действие, без «двойного тапа».
    @objc private func toggleDictation() {
        switch state {
        case .idle:         startDictation()
        case .recording:    stopDictation()
        case .transcribing: break
        }
    }

    /// Хоткей в режиме Toggle: стоп — одиночным нажатием; старт — двойным тапом (если включено),
    /// иначе одиночным. Двойной тап защищает от случайного старта (пункт «переключение»).
    private func hotkeyToggle() {
        switch state {
        case .recording:    stopDictation()
        case .transcribing: break
        case .idle:
            guard Prefs.toggleDoubleTap else { startDictation(); return }
            let now = Date()
            if let last = lastIdleTapAt, now.timeIntervalSince(last) < 0.35 {
                lastIdleTapAt = nil
                startDictation()
            } else {
                lastIdleTapAt = now   // ждём второе нажатие; одиночное ничего не запускает
            }
        }
    }

    private func startDictation() {
        guard state == .idle else { return }
        // ⚠️ Проверяем ДО записи. Сказать «модели нет» после того, как человек наговорил две
        // минуты, — значит потратить его время впустую: расшифровать это будет нечем, а в
        // облако мы такую запись не отправляем (§2.5).
        guard let blocker = setupBlocker() else { return startRecording() }
        offerSetup(blocker)
    }

    /// Диктовать нечем: у локального движка нет модели, у облачного — ключа. Проверяется
    /// ДО записи: сказать это человеку, который уже наговорил две минуты, — потратить его
    /// время впустую, расшифровать эту запись будет нечем.
    private func setupBlocker() -> (title: String, msg: String)? {
        if Prefs.sttEngine == "local" {
            return LocalSTT.isModelAvailable ? nil
                 : (L("alert.noModel.title"), L("alert.noModel.msg"))
        }
        return currentAPIKey() == nil ? (L("alert.noKey.title"), L("alert.noKey.msg")) : nil
    }

    private func startRecording() {
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

    /// Отмена диктовки из плашки (кнопка ×): останавливаем запись и выбрасываем — без распознавания.
    private func cancelDictation() {
        guard state == .recording else { return }
        if let rec = recorder.stop() { try? FileManager.default.removeItem(at: rec.url) }
        state = .idle
    }

    /// Микрофон замолчал посреди диктовки (§3). Записанное ДО отказа — валидный файл, поэтому
    /// распознаём его, а не выбрасываем: сказанное человеком терять нельзя. И говорим об отказе
    /// сразу — иначе он узнает о нём в конце, по обрубленному тексту, когда переговорить уже
    /// нечего. На Windows такой отказ съел у пользователя шесть минут речи из шести с половиной.
    private func handleCaptureDied() {
        guard state == .recording, let rec = recorder.stop() else { return }
        notifyMicDied()
        guard rec.duration >= 0.3 else {
            try? FileManager.default.removeItem(at: rec.url)
            state = .idle
            return
        }
        state = .transcribing
        route(rec: rec)
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
        route(rec: rec)
    }

    /// ⚠️ Облаком НЕ подменяем ни при каких условиях, в том числе пока модель качается.
    /// «Локально (офлайн)» — обещание приватности; нажатие «Скачать модель» согласия отправить
    /// голос в Groq не означает. Вместо подмены — прямое предложение настроить.
    ///
    /// ⚠️ **Второе окно поверх первого не открываем.** В режиме PTT (дефолт macOS) каждое
    /// нажатие клавиши начинает диктовку, поэтому пара нажатий подряд давала пару одинаковых
    /// окон друг на друге. Уже открытое просто поднимаем.
    private func offerSetup(_ blocker: (title: String, msg: String)) {
        guard !isShowingSetupAlert else { return NSApp.activate(ignoringOtherApps: true) }
        isShowingSetupAlert = true
        defer { isShowingSetupAlert = false }
        // ⚠️ Повышаемся до обычного приложения ДО активации и до модального окна, а не после.
        // Приложения-агента нет в списке Cmd+Tab, и активация в этом состоянии там не
        // запоминается; повышение после неё уже ничего не исправляет — приложение впереди,
        // повторная активация ничего не делает, отметки о недавнем использовании так и нет.
        // Живой случай: предупреждение → «Перейти в настройки» → Cmd+Tab возвращал не Voica.
        let wasAccessory = NSApp.activationPolicy() != .regular
        if wasAccessory { setActivationPolicy(.regular, why: "показываем предупреждение") }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = blocker.title
        a.informativeText = blocker.msg
        a.addButton(withTitle: L("alert.noModel.open"))
        a.addButton(withTitle: L("common.cancel"))
        // Окно открываем СЛЕДУЮЩИМ витком цикла: модальная сессия к этому моменту полностью
        // завершена, и активация не спорит с её разбором.
        guard a.runModal() == .alertFirstButtonReturn else {
            // Отказались — окна не будет, значит и обычным приложением быть незачем.
            if wasAccessory, !hasVisibleMainWindow() {
                setActivationPolicy(.accessory, why: "предупреждение закрыто без окна")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in self?.settingsWindow.showGeneral() }
    }

    /// Куда отправить запись: локальный движок, облако или никуда.
    ///
    /// ⚠️ **Выбран локальный движок, а модели нет — В ОБЛАКО НЕ ОТПРАВЛЯЕМ, никогда.**
    /// «Локально (офлайн)» это обещание приватности, и тихо нарушить его хуже, чем отказать:
    /// человек видит на переключателе «офлайн», а звук уезжает в Groq. Поймано живой проверкой —
    /// после удаления модели диктовка ушла в облако, и в истории осталось `whisper-large-v3`.
    ///
    /// Сюда в норме не доходят: старт диктовки такую запись не начнёт. Проверка остаётся
    /// подстраховкой на случай, когда модель удалили уже во время записи.
    private func route(rec: (url: URL, duration: TimeInterval)) {
        guard Prefs.sttEngine == "local" else { return transcribeViaCloud(rec: rec) }
        if LocalSTT.isModelAvailable { return transcribeLocally(rec: rec) }
        state = .idle
        try? FileManager.default.removeItem(at: rec.url)
        offerSetup((L("alert.noModel.title"), L("alert.noModel.msg")))
    }

    private func transcribeViaCloud(rec: (url: URL, duration: TimeInterval)) {
        GroqClient.transcribe(fileURL: rec.url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let t):
                    self.handleTranscribed(t, rec: rec, model: GroqClient.sttModel)
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
        // Если модель ещё не в памяти — первая загрузка займёт десятки секунд (разовая
        // подгонка под чип). Показываем HUD, иначе похоже на зависание.
        let showingPrep = !LocalSTT.shared.isModelLoaded
        if showingPrep { prepHUD.show(L("hud.preparingModel")) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> Transcription in
                let signal = try LocalSTT.loadWav16k(rec.url)
                let text = try LocalSTT.shared.transcribe(signal)
                return Transcription(text: text, language: "ru", duration: rec.duration)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if showingPrep { self.prepHUD.hide() }
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
    private func handleTranscribed(_ raw: Transcription, rec: (url: URL, duration: TimeInterval),
                                   model: String) {
        // §6: детерминированная нормализация — правилами, до ИИ-правки и независимо от неё.
        // Работает на обоих движках, без ключа и без сети. Для локального движка это вообще
        // единственный бесплатный путь: словарь-подсказка `prompt` — фича облачного Whisper.
        var cleaned = raw.text
        if Prefs.stripFillers { cleaned = Normalizer.stripFillers(cleaned) }
        if Prefs.fixTermsByRules { cleaned = Normalizer.fixTerms(cleaned, vocabulary: Prefs.vocabulary) }
        let t = Transcription(text: cleaned, language: raw.language, duration: raw.duration)
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
                    self?.deliver(text: final, transcription: t, rec: rec, model: model,
                                  raw: raw.text)
                }
            }
        } else {
            // Сырой текст сохраняем и без ИИ: правила тоже меняют текст, и без исходника
            // потом не разобрать, кто именно наследил. Нормализация детерминирована, поэтому
            // промежуточное состояние всегда можно воспроизвести из сырого заново.
            deliver(text: t.text, transcription: t, rec: rec, model: model, raw: raw.text)
        }
    }

    /// Системное уведомление о переходе на локальную модель (без модальных окон,
    /// чтобы не мешать диктовке). Если уведомления запрещены — просто лог.
    /// 403 от chat-модели: она есть у Groq, но не разрешена организации пользователя.
    /// Постобработка при этом молча возвращает исходный текст — без уведомления человек
    /// решил бы, что исправление терминов просто не работает.
    private func notifyChatModelBlocked(_ model: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else {
                NSLog("Voica: chat-модель %@ заблокирована в Groq-организации", model)
                return
            }
            let content = UNMutableNotificationContent()
            content.title = L("notify.chatBlocked.title")
            content.body = L("notify.chatBlocked.body", model)
            center.add(UNNotificationRequest(identifier: "voica-chat-blocked",
                                             content: content, trigger: nil))
        }
    }

    /// Отказ микрофона — системным уведомлением, без модального окна: диктовка в этот момент
    /// уже переходит в распознавание, и модалка перехватила бы фокус ровно тогда, когда текст
    /// собирается вставляться.
    private func notifyMicDied() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else {
                NSLog("Voica: микрофон перестал отдавать звук — распознаю записанное")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = L("notify.micdied.title")
            content.body = L("notify.micdied.body")
            center.add(UNNotificationRequest(identifier: "voica-mic-died",
                                             content: content, trigger: nil))
        }
    }

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
    /// `raw` — текст движка ДО любой нашей обработки (и правил §6.2, и ИИ §6.1).
    /// В историю он попадает, только когда реально отличается от доставленного (§7):
    /// две одинаковые копии не нужны, а каждая пара «raw → text» — готовый случай для разбора.
    private func deliver(text rawText: String, transcription t: Transcription,
                         rec: (url: URL, duration: TimeInterval), model: String,
                         raw: String? = nil) {
        // Последняя проверка перед выдачей (§6.4): непарную кавычку мог оставить и движок,
        // и модель, поэтому чистим здесь — после обоих, в единственной точке выдачи.
        let text = Prefs.fixQuotes ? Normalizer.balanceQuotes(rawText) : rawText
        state = .idle
        Store.shared.insert(text: text, language: t.language,
                            duration: t.duration ?? rec.duration,
                            model: model, audioTempURL: rec.url,
                            rawText: (raw != text) ? raw : nil)
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

    /// Cmd+F: открыть историю, если закрыта, и поставить курсор в поиск.
    @objc private func findInHistory() {
        if historyWindow.window?.isVisible != true { historyWindow.reloadAndShow() }
        historyWindow.focusSearch()
    }
    @objc private func showSettings() { settingsWindow.show() }

    @objc private func showAbout() { settingsWindow.showAbout() }

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

// Диагностика уведомлений: статус разрешения + пробный баннер.
if CommandLine.arguments.contains("--notify-test") {
    _ = NSApplication.shared
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { s in
        print("authorizationStatus =", s.authorizationStatus.rawValue,
              "(0 notDetermined, 1 denied, 2 authorized, 3 provisional)")
        print("alertSetting =", s.alertSetting.rawValue, "(0 notSupported, 1 disabled, 2 enabled)")
        center.requestAuthorization(options: [.alert]) { granted, err in
            print("requestAuthorization granted =", granted,
                  "err =", err?.localizedDescription ?? "нет")
            let c = UNMutableNotificationContent()
            c.title = "Voica — проверка уведомлений"
            c.body = "Если ты это видишь, доставка работает."
            center.add(UNNotificationRequest(identifier: "voica-notify-test", content: c, trigger: nil)) { e in
                print("add error =", e?.localizedDescription ?? "нет")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
            }
        }
    }
    RunLoop.main.run()
}

// Служебный режим: скачать и установить локальную модель без GUI.
// Проверяет весь конвейер загрузчика (сеть → SHA-256 → распаковка) на настоящем
// release-ассете; $VOICA_GIGAAM_URL переопределяет источник.
// Скрытый флаг разработчика: прогнать готовый WAV 16 кГц моно через локальный движок и
// напечатать текст. Нужен, чтобы проверять правки склейки чанков на СОХРАНЁННОМ аудио, а не
// переговаривать диктовку заново — иначе изменения в тексте не отличить от новой записи.
// Заодно это заготовка под «Transcribe audio file…» из планов на 1.0.
if let i = CommandLine.arguments.firstIndex(of: "--transcribe"),
   i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    guard LocalSTT.isModelAvailable else {
        print("Локальная модель не установлена (--fetch-model)")
        exit(1)
    }
    do {
        let sig = try LocalSTT.loadWav16k(URL(fileURLWithPath: path))
        let start = Date()
        let text = try LocalSTT.shared.transcribe(sig)
        FileHandle.standardError.write(String(format: "· %.1f с аудио, распознано за %.1f с\n",
                                              Double(sig.count) / 16000.0,
                                              -start.timeIntervalSinceNow).data(using: .utf8)!)
        print(text)
        exit(0)
    } catch {
        print("Ошибка: \(error.localizedDescription)")
        exit(1)
    }
}

// Печатает промпт ИИ-исправления для заданных словаря и текста. Нужен скрипту сравнения
// chat-моделей: иначе промпт пришлось бы копировать в скрипт, и он бы разошёлся с рабочим,
// а замер молча начал бы измерять не то.
if let i = CommandLine.arguments.firstIndex(of: "--print-prompt"),
   i + 2 < CommandLine.arguments.count {
    guard let p = GroqClient.postProcessPrompt(text: CommandLine.arguments[i + 2],
                                               vocabulary: CommandLine.arguments[i + 1]) else {
        FileHandle.standardError.write("пустой словарь\n".data(using: .utf8)!); exit(1)
    }
    print(p)
    exit(0)
}

// Прогон нормализатора по файлу со строками: печатает только то, что изменилось.
// Нужен, чтобы проверять правила на настоящей истории, а не на придуманных примерах —
// ложное срабатывание на обычной речи иначе не поймать.
if let i = CommandLine.arguments.firstIndex(of: "--normalize-corpus"),
   i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    guard let body = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write("не прочитать \(path)\n".data(using: .utf8)!); exit(1)
    }
    let lines = body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    var changed = 0
    for line in lines {
        // Тот же порядок, что в диктовке: сперва филлеры, потом термины.
        var after = line
        if Prefs.stripFillers { after = Normalizer.stripFillers(after) }
        if Prefs.fixTermsByRules { after = Normalizer.fixTerms(after, vocabulary: Prefs.vocabulary) }
        if Prefs.fixQuotes { after = Normalizer.balanceQuotes(after) }
        if after != line {
            changed += 1
            print("— \(line)\n+ \(after)\n")
        }
    }
    print("строк: \(lines.count), изменено: \(changed)")
    exit(0)
}

if CommandLine.arguments.contains("--fetch-model") {
    print("Качаю \(ModelDownloader.downloadURL.absoluteString)")
    var ok = false
    ModelDownloader.shared.onProgress = { p in
        print(String(format: "\r%3d%%", Int(p * 100)), terminator: "")
        fflush(stdout)
    }
    ModelDownloader.shared.onFinish = { outcome in
        print("")
        switch outcome {
        case .success:
            print("Модель установлена: \(ModelDownloader.modelsDir().path)")
            ok = true
        case .cancelled:
            print("Отменено")
        case .failure(let msg):
            print("Ошибка: \(msg)")
        }
        CFRunLoopStop(CFRunLoopGetMain())
    }
    ModelDownloader.shared.start()
    CFRunLoopRun()   // коллбэки приходят на главный поток — крутим его run loop
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // меню-бар агент, без иконки в доке
let delegate = AppDelegate()
app.delegate = delegate
app.run()
