// Окно настроек: API-ключ (защищённый файл), режим/клавиша диктовки, хранение аудио,
// полное удаление данных с подтверждением случайной фразой.

import Cocoa

final class SettingsWindowController: NSWindowController, NSTextViewDelegate, NSWindowDelegate {
    /// Вызывается после изменения настроек хоткея, чтобы применить их вживую.
    var onHotkeySettingsChanged: (() -> Void)?

    private var secureKeyField: NSSecureTextField!
    private var plainKeyField: NSTextField!
    private var showKeyToggle: NSButton!
    private var keyStatusLabel: NSTextField!
    private var statusIcon: NSImageView!
    private var statusSpinner: NSProgressIndicator!

    private enum StatusKind { case neutral, success, error }

    private var modeControl: NSSegmentedControl!
    private var outputControl: NSSegmentedControl!
    private var keyPopup: NSPopUpButton!
    private var storeAudioToggle: NSButton!
    private var retentionField: NSTextField!
    private var checkUpdatesToggle: NSButton!
    private var vocabTextView: NSTextView!

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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L("settings.title")
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("voica-main")
        self.init(window: window)
        buildUI()
        window.delegate = self
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
        ])

        // — API-ключ —
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
        statusSpinner = NSProgressIndicator()
        statusSpinner.style = .spinning
        statusSpinner.controlSize = .small
        statusSpinner.isDisplayedWhenStopped = false
        statusSpinner.translatesAutoresizingMaskIntoConstraints = false
        statusSpinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        statusSpinner.heightAnchor.constraint(equalToConstant: 16).isActive = true

        statusIcon = NSImageView()
        statusIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        statusIcon.isHidden = true

        keyStatusLabel = NSTextField(labelWithString: "")
        keyStatusLabel.font = .systemFont(ofSize: 11)
        keyStatusLabel.textColor = .secondaryLabelColor

        let keyBtnRow = NSStackView(views: [saveBtn, testBtn, statusSpinner, statusIcon, keyStatusLabel])
        keyBtnRow.spacing = 6
        stack.addArrangedSubview(keyBtnRow)

        let hint = NSTextField(labelWithString: L("settings.key.hint"))
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)

        stack.addArrangedSubview(separator())

        // — Диктовка —
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

        let outputHint = NSTextField(labelWithString: L("settings.output.hint"))
        outputHint.font = .systemFont(ofSize: 10)
        outputHint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(outputHint)

        stack.addArrangedSubview(separator())

        // — Словарь терминов —
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

        let vocabHint = NSTextField(wrappingLabelWithString: L("settings.vocab.hint"))
        vocabHint.font = .systemFont(ofSize: 10)
        vocabHint.textColor = .tertiaryLabelColor
        vocabHint.widthAnchor.constraint(equalToConstant: 424).isActive = true
        stack.addArrangedSubview(vocabHint)

        stack.addArrangedSubview(separator())

        // — Аудио —
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

        // — Обновления —
        stack.addArrangedSubview(header(L("settings.updates.header")))
        checkUpdatesToggle = NSButton(checkboxWithTitle: L("settings.updates.onLaunch"),
                                      target: self, action: #selector(checkUpdatesChanged))
        stack.addArrangedSubview(checkUpdatesToggle)

        stack.addArrangedSubview(separator())

        // — Данные —
        stack.addArrangedSubview(header(L("settings.data.header")))
        let deleteBtn = NSButton(title: L("settings.data.deleteAll"), target: self, action: #selector(deleteAllData))
        deleteBtn.hasDestructiveAction = true
        stack.addArrangedSubview(deleteBtn)
    }

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

    // MARK: - Показ / загрузка значений

    func showAndFocusKey() {
        populate()
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
        setStatus(key.isEmpty ? L("settings.key.status.none") : L("settings.key.status.saved"), .neutral)

        modeControl.selectedSegment = (Prefs.dictationMode == "toggle") ? 1 : 0
        if let idx = modifierChoices.firstIndex(where: { $0.1 == Prefs.pttKeyCode }) {
            keyPopup.selectItem(at: idx)
        }
        outputControl.selectedSegment = (Prefs.outputMode == "window") ? 1 : 0
        storeAudioToggle.state = Prefs.storeAudio ? .on : .off
        retentionField.integerValue = Prefs.retentionDays
        checkUpdatesToggle.state = Prefs.checkUpdatesOnLaunch ? .on : .off
        vocabTextView.string = Prefs.vocabulary
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

    private func setStatus(_ text: String, _ kind: StatusKind = .neutral) {
        statusSpinner.stopAnimation(nil)
        keyStatusLabel.stringValue = text
        switch kind {
        case .neutral:
            statusIcon.isHidden = true
        case .success:
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusIcon.isHidden = false
        case .error:
            statusIcon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemRed
            statusIcon.isHidden = false
        }
    }

    private func setChecking(_ text: String) {
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
            setStatus(L("settings.key.status.empty"), .error)
            return
        }
        if KeyStore.save(key) {
            setStatus(L("settings.key.status.savedNow"), .success)
        } else {
            setStatus(L("settings.key.status.saveFailed"), .error)
        }
    }

    @objc private func testKey() {
        let key = keyFieldValue
        guard !key.isEmpty else {
            setStatus(L("settings.key.status.empty"), .error)
            return
        }
        setChecking(L("settings.key.status.checking"))
        GroqClient.validateKey(key) { [weak self] problem in
            DispatchQueue.main.async {
                if let problem {
                    self?.setStatus(L("settings.key.status.invalid", problem), .error)
                } else {
                    self?.setStatus(L("settings.key.status.valid"), .success)
                }
            }
        }
    }

    // MARK: - Действия: диктовка / аудио

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
