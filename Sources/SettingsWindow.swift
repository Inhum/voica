// Окно настроек: вкладки в стиле системных настроек macOS (toolbar-style, как Tailscale).
// General — ключ Groq и обновления; Dictation — режим/клавиша/вывод;
// Vocabulary — словарь и ИИ-исправление (с проверкой доступности модели);
// Data — аудио и полное удаление данных (с подтверждением случайной фразой).

import Cocoa

final class SettingsWindowController: NSWindowController, NSTextViewDelegate, NSWindowDelegate {
    /// Вызывается после изменения настроек хоткея, чтобы применить их вживую.
    var onHotkeySettingsChanged: (() -> Void)?

    // General
    private var secureKeyField: NSSecureTextField!
    private var plainKeyField: NSTextField!
    private var showKeyToggle: NSButton!
    private var keyStatusLabel: NSTextField!
    private var statusIcon: NSImageView!
    private var statusSpinner: NSProgressIndicator!
    private var checkUpdatesToggle: NSButton!

    // Dictation
    private var modeControl: NSSegmentedControl!
    private var outputControl: NSSegmentedControl!
    private var keyPopup: NSPopUpButton!

    // Vocabulary
    private var vocabTextView: NSTextView!
    private var vocabCounter: NSTextField!
    private var llmToggle: NSButton!
    private var llmStatusLabel: NSTextField!
    private var llmStatusIcon: NSImageView!
    private var llmSpinner: NSProgressIndicator!

    // Data
    private var storeAudioToggle: NSButton!
    private var retentionField: NSTextField!

    private var tabs: NSTabViewController!

    private enum StatusKind { case neutral, success, error, warning }

    // (заголовок, keyCode)
    private let modifierChoices: [(String, Int)] = [
        (L("modifier.rightOption"), 61),
        (L("modifier.leftOption"), 58),
        (L("modifier.rightCommand"), 54),
        (L("modifier.leftCommand"), 55),
        (L("modifier.rightControl"), 62),
        (L("modifier.function"), 63),
    ]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L("settings.title")
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("voica-main")
        window.toolbarStyle = .preference
        self.init(window: window)
        buildUI()
        window.delegate = self
    }

    // MARK: - Вкладки

    private func buildUI() {
        tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false   // держим общий заголовок окна

        addTab(L("settings.tab.general"),   symbol: "gearshape",             view: buildGeneralTab())
        addTab(L("settings.tab.dictation"), symbol: "mic",                   view: buildDictationTab())
        addTab(L("settings.tab.vocab"),     symbol: "character.book.closed", view: buildVocabularyTab())
        addTab(L("settings.tab.data"),      symbol: "internaldrive",         view: buildDataTab())

        window?.contentViewController = tabs
    }

    private func addTab(_ label: String, symbol: String, view: NSView) {
        let vc = NSViewController()
        vc.view = view
        view.layoutSubtreeIfNeeded()
        vc.preferredContentSize = view.fittingSize   // окно меняет высоту под вкладку
        let item = NSTabViewItem(viewController: vc)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        tabs.addTabViewItem(item)
    }

    /// Контейнер вкладки: вертикальный стек с полями 18pt, ширина контента 424.
    private func tabContainer() -> (NSView, NSStackView) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 460).isActive = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])
        return (container, stack)
    }

    // MARK: - Вкладка General (ключ + обновления)

    private func buildGeneralTab() -> NSView {
        let (container, stack) = tabContainer()

        stack.addArrangedSubview(header(L("settings.key.header")))

        secureKeyField = NSSecureTextField()
        secureKeyField.placeholderString = "gsk_…"
        plainKeyField = NSTextField()
        plainKeyField.placeholderString = "gsk_…"
        plainKeyField.isHidden = true
        for f: NSTextField in [secureKeyField, plainKeyField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }
        showKeyToggle = NSButton(checkboxWithTitle: L("settings.key.show"), target: self, action: #selector(toggleShowKey))

        let keyRow = NSStackView(views: [secureKeyField, plainKeyField, showKeyToggle])
        keyRow.spacing = 8
        stack.addArrangedSubview(keyRow)

        let saveBtn = NSButton(title: L("settings.key.save"), target: self, action: #selector(saveKey))
        let testBtn = NSButton(title: L("settings.key.test"), target: self, action: #selector(testKey))
        statusSpinner = makeSpinner()
        statusIcon = makeStatusIcon()
        keyStatusLabel = makeStatusLabel()

        let keyBtnRow = NSStackView(views: [saveBtn, testBtn, statusSpinner, statusIcon, keyStatusLabel])
        keyBtnRow.spacing = 6
        stack.addArrangedSubview(keyBtnRow)

        let hint = makeHint(L("settings.key.hint"))
        stack.addArrangedSubview(hint)

        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(header(L("settings.updates.header")))
        checkUpdatesToggle = NSButton(checkboxWithTitle: L("settings.updates.onLaunch"),
                                      target: self, action: #selector(checkUpdatesChanged))
        stack.addArrangedSubview(checkUpdatesToggle)

        stack.addArrangedSubview(separator())

        let resetBtn = NSButton(title: L("settings.reset.button"), target: self,
                                action: #selector(resetSettings))
        stack.addArrangedSubview(resetBtn)
        stack.addArrangedSubview(makeHint(L("settings.reset.hint")))

        return container
    }

    // MARK: - Вкладка Dictation (режим / клавиша / вывод)

    private func buildDictationTab() -> NSView {
        let (container, stack) = tabContainer()

        stack.addArrangedSubview(header(L("settings.dictation.header")))

        modeControl = NSSegmentedControl(labels: [L("settings.mode.ptt"), L("settings.mode.toggle")],
                                         trackingMode: .selectOne, target: self,
                                         action: #selector(modeChanged))
        stack.addArrangedSubview(labeledRow(L("settings.mode.label"), modeControl))

        keyPopup = NSPopUpButton()
        keyPopup.addItems(withTitles: modifierChoices.map { $0.0 })
        keyPopup.target = self
        keyPopup.action = #selector(keyChoiceChanged)
        stack.addArrangedSubview(labeledRow(L("settings.keyChoice.label"), keyPopup))

        outputControl = NSSegmentedControl(labels: [L("settings.output.insert"), L("settings.output.window")],
                                           trackingMode: .selectOne, target: self,
                                           action: #selector(outputChanged))
        stack.addArrangedSubview(labeledRow(L("settings.output.label"), outputControl))

        stack.addArrangedSubview(makeHint(L("settings.output.hint")))

        return container
    }

    // MARK: - Вкладка Vocabulary (словарь + ИИ-исправление)

    private func buildVocabularyTab() -> NSView {
        let (container, stack) = tabContainer()

        stack.addArrangedSubview(header(L("settings.vocab.header")))

        let vocabScroll = NSScrollView()
        vocabScroll.translatesAutoresizingMaskIntoConstraints = false
        vocabScroll.hasVerticalScroller = true
        vocabScroll.borderType = .bezelBorder
        vocabScroll.widthAnchor.constraint(equalToConstant: 424).isActive = true
        vocabScroll.heightAnchor.constraint(equalToConstant: 60).isActive = true
        let vtv = NSTextView()
        vtv.isRichText = false
        vtv.font = .systemFont(ofSize: 12)
        vtv.textContainerInset = NSSize(width: 4, height: 4)
        vtv.autoresizingMask = [.width]
        vtv.delegate = self
        vocabScroll.documentView = vtv
        vocabTextView = vtv
        stack.addArrangedSubview(vocabScroll)

        vocabCounter = NSTextField(labelWithString: "")
        vocabCounter.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        vocabCounter.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(vocabCounter)

        stack.addArrangedSubview(makeHint(L("settings.vocab.hint")))

        llmToggle = NSButton(checkboxWithTitle: L("settings.vocab.llm"),
                             target: self, action: #selector(llmChanged))
        stack.addArrangedSubview(llmToggle)

        llmSpinner = makeSpinner()
        llmStatusIcon = makeStatusIcon()
        llmStatusLabel = makeStatusLabel()
        let llmStatusRow = NSStackView(views: [llmSpinner, llmStatusIcon, llmStatusLabel])
        llmStatusRow.spacing = 6
        stack.addArrangedSubview(llmStatusRow)

        stack.addArrangedSubview(makeHint(L("settings.vocab.llm.hint")))

        return container
    }

    // MARK: - Вкладка Data (аудио + удаление)

    private func buildDataTab() -> NSView {
        let (container, stack) = tabContainer()

        stack.addArrangedSubview(header(L("settings.audio.header")))

        storeAudioToggle = NSButton(checkboxWithTitle: L("settings.audio.store"),
                                    target: self, action: #selector(storeAudioChanged))
        stack.addArrangedSubview(storeAudioToggle)

        retentionField = NSTextField()
        retentionField.translatesAutoresizingMaskIntoConstraints = false
        retentionField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        retentionField.target = self
        retentionField.action = #selector(retentionChanged)
        let retLabel = NSTextField(labelWithString: L("settings.audio.retentionPrefix"))
        let daysLabel = NSTextField(labelWithString: L("settings.audio.retentionSuffix"))
        daysLabel.textColor = .secondaryLabelColor
        let retRow = NSStackView(views: [retLabel, retentionField, daysLabel])
        retRow.spacing = 6
        stack.addArrangedSubview(retRow)

        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(header(L("settings.data.header")))
        let deleteBtn = NSButton(title: L("settings.data.deleteAll"), target: self, action: #selector(deleteAllData))
        deleteBtn.hasDestructiveAction = true
        stack.addArrangedSubview(deleteBtn)

        return container
    }

    // MARK: - UI-помощники

    private func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return box
    }

    private func labeledRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let row = NSStackView(views: [label, control])
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func makeHint(_ text: String) -> NSTextField {
        let hint = NSTextField(wrappingLabelWithString: text)
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return hint
    }

    private func makeSpinner() -> NSProgressIndicator {
        let s = NSProgressIndicator()
        s.style = .spinning
        s.controlSize = .small
        s.isDisplayedWhenStopped = false
        s.translatesAutoresizingMaskIntoConstraints = false
        s.widthAnchor.constraint(equalToConstant: 16).isActive = true
        s.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return s
    }

    private func makeStatusIcon() -> NSImageView {
        let icon = NSImageView()
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.isHidden = true
        return icon
    }

    private func makeStatusLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func applyStatus(icon: NSImageView, spinner: NSProgressIndicator,
                             label: NSTextField, text: String, kind: StatusKind) {
        spinner.stopAnimation(nil)
        label.stringValue = text
        switch kind {
        case .neutral:
            icon.isHidden = true
        case .success:
            icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemGreen
            icon.isHidden = false
        case .error:
            icon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemRed
            icon.isHidden = false
        case .warning:
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemOrange
            icon.isHidden = false
        }
    }

    // MARK: - Показ / загрузка значений

    func showAndFocusKey() {
        populate()
        tabs.selectedTabViewItemIndex = 0   // General — там ключ
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(secureKeyField)
    }

    func show() {
        populate()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func populate() {
        let key = KeyStore.load() ?? ""
        secureKeyField.stringValue = key
        plainKeyField.stringValue = key
        setKeyStatus(key.isEmpty ? L("settings.key.status.none") : L("settings.key.status.saved"), .neutral)

        modeControl.selectedSegment = (Prefs.dictationMode == "toggle") ? 1 : 0
        if let idx = modifierChoices.firstIndex(where: { $0.1 == Prefs.pttKeyCode }) {
            keyPopup.selectItem(at: idx)
        }
        outputControl.selectedSegment = (Prefs.outputMode == "window") ? 1 : 0
        storeAudioToggle.state = Prefs.storeAudio ? .on : .off
        retentionField.integerValue = Prefs.retentionDays
        checkUpdatesToggle.state = Prefs.checkUpdatesOnLaunch ? .on : .off
        vocabTextView.string = Prefs.vocabulary
        updateVocabCounter()
        llmToggle.state = Prefs.llmPostProcess ? .on : .off
        if Prefs.llmPostProcess { verifyChatModel() } else { clearLLMStatus() }
    }

    /// Живой счётчик символов словаря относительно бюджета prompt.
    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === vocabTextView else { return }
        updateVocabCounter()
    }

    private func updateVocabCounter() {
        let n = vocabTextView.string.count
        let budget = GroqClient.promptCharBudget
        vocabCounter.stringValue = L("settings.vocab.counter", n, budget)
        vocabCounter.textColor = n > budget ? .systemOrange : .tertiaryLabelColor
    }

    /// Словарь сохраняем по потере фокуса полем (NSTextView).
    func textDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextView) === vocabTextView else { return }
        Prefs.vocabulary = vocabTextView.string
    }

    /// Подстраховка: зафиксировать словарь при закрытии окна, если end-editing не успел.
    func windowWillClose(_ notification: Notification) {
        if let s = vocabTextView?.string { Prefs.vocabulary = s }
    }

    private var keyFieldValue: String {
        (showKeyToggle.state == .on ? plainKeyField.stringValue : secureKeyField.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setKeyStatus(_ text: String, _ kind: StatusKind = .neutral) {
        applyStatus(icon: statusIcon, spinner: statusSpinner, label: keyStatusLabel, text: text, kind: kind)
    }

    private func setKeyChecking(_ text: String) {
        statusIcon.isHidden = true
        keyStatusLabel.stringValue = text
        statusSpinner.startAnimation(nil)
    }

    // MARK: - Действия: ключ

    @objc private func toggleShowKey() {
        if showKeyToggle.state == .on {
            plainKeyField.stringValue = secureKeyField.stringValue
            plainKeyField.isHidden = false
            secureKeyField.isHidden = true
        } else {
            secureKeyField.stringValue = plainKeyField.stringValue
            secureKeyField.isHidden = false
            plainKeyField.isHidden = true
        }
    }

    @objc private func saveKey() {
        let key = keyFieldValue
        guard !key.isEmpty else {
            setKeyStatus(L("settings.key.status.empty"), .error)
            return
        }
        if KeyStore.save(key) {
            setKeyStatus(L("settings.key.status.savedNow"), .success)
        } else {
            setKeyStatus(L("settings.key.status.saveFailed"), .error)
        }
    }

    @objc private func testKey() {
        let key = keyFieldValue
        guard !key.isEmpty else {
            setKeyStatus(L("settings.key.status.empty"), .error)
            return
        }
        setKeyChecking(L("settings.key.status.checking"))
        GroqClient.validateKey(key) { [weak self] problem in
            DispatchQueue.main.async {
                if let problem {
                    self?.setKeyStatus(L("settings.key.status.invalid", problem), .error)
                } else {
                    self?.setKeyStatus(L("settings.key.status.valid"), .success)
                }
            }
        }
    }

    // MARK: - Действия: диктовка / аудио / обновления

    @objc private func modeChanged() {
        Prefs.dictationMode = (modeControl.selectedSegment == 1) ? "toggle" : "ptt"
        onHotkeySettingsChanged?()
    }

    @objc private func keyChoiceChanged() {
        Prefs.pttKeyCode = modifierChoices[keyPopup.indexOfSelectedItem].1
        onHotkeySettingsChanged?()
    }

    @objc private func outputChanged() {
        Prefs.outputMode = (outputControl.selectedSegment == 1) ? "window" : "insert"
    }

    @objc private func storeAudioChanged() {
        Prefs.storeAudio = (storeAudioToggle.state == .on)
    }

    @objc private func checkUpdatesChanged() {
        Prefs.checkUpdatesOnLaunch = (checkUpdatesToggle.state == .on)
    }

    @objc private func retentionChanged() {
        Prefs.retentionDays = max(0, retentionField.integerValue)
        retentionField.integerValue = Prefs.retentionDays
    }

    // MARK: - Действия: ИИ-исправление (verify доступности модели)

    @objc private func llmChanged() {
        Prefs.llmPostProcess = (llmToggle.state == .on)
        if Prefs.llmPostProcess { verifyChatModel() } else { clearLLMStatus() }
    }

    private func verifyChatModel() {
        llmStatusIcon.isHidden = true
        llmStatusLabel.stringValue = L("settings.vocab.llm.checking")
        llmSpinner.startAnimation(nil)
        GroqClient.validateChatModel { [weak self] problem in
            DispatchQueue.main.async {
                guard let self else { return }
                if let problem {
                    self.applyStatus(icon: self.llmStatusIcon, spinner: self.llmSpinner,
                                     label: self.llmStatusLabel, text: problem, kind: .warning)
                } else {
                    self.applyStatus(icon: self.llmStatusIcon, spinner: self.llmSpinner,
                                     label: self.llmStatusLabel,
                                     text: L("settings.vocab.llm.ok"), kind: .success)
                }
            }
        }
    }

    private func clearLLMStatus() {
        llmSpinner.stopAnimation(nil)
        llmStatusIcon.isHidden = true
        llmStatusLabel.stringValue = ""
    }

    // MARK: - Сброс настроек (ключ, история и аудио не трогаются)

    @objc private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = L("settings.reset.title")
        alert.informativeText = L("settings.reset.msg")
        alert.addButton(withTitle: L("settings.reset.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let vocab = Prefs.vocabulary   // словарь — пользовательский контент, не настройка
        Prefs.reset()
        Prefs.vocabulary = vocab
        populate()
        onHotkeySettingsChanged?()
    }

    // MARK: - Delete all data

    @objc private func deleteAllData() {
        let counts = Store.shared.counts()
        let phrase = "delete-\(String(UUID().uuidString.prefix(4)).lowercased())"

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L("deleteAll.title")
        alert.informativeText = L("deleteAll.body", counts.records, counts.audioFiles, phrase)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L("deleteAll.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard field.stringValue.trimmingCharacters(in: .whitespaces) == phrase else {
            let mismatch = NSAlert()
            mismatch.messageText = L("deleteAll.mismatch.title")
            mismatch.informativeText = L("deleteAll.mismatch.msg")
            mismatch.runModal()
            return
        }

        Store.shared.deleteAll()
        KeyStore.delete()
        Prefs.reset()
        populate()
        onHotkeySettingsChanged?()

        let done = NSAlert()
        done.messageText = L("deleteAll.done.title")
        done.informativeText = L("deleteAll.done.msg")
        done.runModal()
    }
}
