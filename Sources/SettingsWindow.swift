// Окно настроек: API-ключ (Keychain), режим/клавиша диктовки, хранение аудио,
// полное удаление данных с подтверждением случайной фразой.

import Cocoa

final class SettingsWindowController: NSWindowController {
    /// Вызывается после изменения настроек хоткея, чтобы применить их вживую.
    var onHotkeySettingsChanged: (() -> Void)?

    private var secureKeyField: NSSecureTextField!
    private var plainKeyField: NSTextField!
    private var showKeyToggle: NSButton!
    private var keyStatusLabel: NSTextField!

    private var modeControl: NSSegmentedControl!
    private var keyPopup: NSPopUpButton!
    private var storeAudioToggle: NSButton!
    private var retentionField: NSTextField!

    // (заголовок, keyCode)
    private let modifierChoices: [(String, Int)] = [
        ("Правый ⌥ Option", 61),
        ("Левый ⌥ Option", 58),
        ("Правый ⌘ Command", 54),
        ("Левый ⌘ Command", 55),
        ("Правый ⌃ Control", 62),
        ("fn / 🌐 Globe", 63),
    ]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Voica — Настройки"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("voica-main")
        self.init(window: window)
        buildUI()
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
        stack.addArrangedSubview(header("Groq API-ключ"))

        secureKeyField = NSSecureTextField()
        secureKeyField.placeholderString = "gsk_…"
        plainKeyField = NSTextField()
        plainKeyField.placeholderString = "gsk_…"
        plainKeyField.isHidden = true
        for f: NSTextField in [secureKeyField, plainKeyField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }
        showKeyToggle = NSButton(checkboxWithTitle: "Показать", target: self, action: #selector(toggleShowKey))

        let keyRow = NSStackView(views: [secureKeyField, plainKeyField, showKeyToggle])
        keyRow.spacing = 8
        stack.addArrangedSubview(keyRow)

        let saveBtn = NSButton(title: "Сохранить", target: self, action: #selector(saveKey))
        let testBtn = NSButton(title: "Проверить", target: self, action: #selector(testKey))
        keyStatusLabel = NSTextField(labelWithString: "")
        keyStatusLabel.font = .systemFont(ofSize: 11)
        keyStatusLabel.textColor = .secondaryLabelColor
        let keyBtnRow = NSStackView(views: [saveBtn, testBtn, keyStatusLabel])
        keyBtnRow.spacing = 8
        stack.addArrangedSubview(keyBtnRow)

        let hint = NSTextField(labelWithString: "Ключ сохраняется кнопкой «Сохранить». Остальные настройки применяются сразу.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)

        stack.addArrangedSubview(separator())

        // — Диктовка —
        stack.addArrangedSubview(header("Диктовка"))

        modeControl = NSSegmentedControl(labels: ["PTT (удержание)", "Toggle (вкл/выкл)"],
                                         trackingMode: .selectOne, target: self,
                                         action: #selector(modeChanged))
        stack.addArrangedSubview(labeledRow("Режим:", modeControl))

        keyPopup = NSPopUpButton()
        keyPopup.addItems(withTitles: modifierChoices.map { $0.0 })
        keyPopup.target = self
        keyPopup.action = #selector(keyChoiceChanged)
        stack.addArrangedSubview(labeledRow("Клавиша:", keyPopup))

        stack.addArrangedSubview(separator())

        // — Аудио —
        stack.addArrangedSubview(header("Аудио"))

        storeAudioToggle = NSButton(checkboxWithTitle: "Хранить аудиозаписи",
                                    target: self, action: #selector(storeAudioChanged))
        stack.addArrangedSubview(storeAudioToggle)

        retentionField = NSTextField()
        retentionField.translatesAutoresizingMaskIntoConstraints = false
        retentionField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        retentionField.target = self
        retentionField.action = #selector(retentionChanged)
        let retLabel = NSTextField(labelWithString: "Удалять аудио старше")
        let daysLabel = NSTextField(labelWithString: "дней (0 = хранить всегда)")
        daysLabel.textColor = .secondaryLabelColor
        let retRow = NSStackView(views: [retLabel, retentionField, daysLabel])
        retRow.spacing = 6
        stack.addArrangedSubview(retRow)

        stack.addArrangedSubview(separator())

        // — Данные —
        stack.addArrangedSubview(header("Данные"))
        let deleteBtn = NSButton(title: "Delete all data…", target: self, action: #selector(deleteAllData))
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
        let key = Keychain.load() ?? ""
        secureKeyField.stringValue = key
        plainKeyField.stringValue = key
        keyStatusLabel.stringValue = key.isEmpty ? "Ключ не задан" : "Ключ сохранён"

        modeControl.selectedSegment = (Prefs.dictationMode == "toggle") ? 1 : 0
        if let idx = modifierChoices.firstIndex(where: { $0.1 == Prefs.pttKeyCode }) {
            keyPopup.selectItem(at: idx)
        }
        storeAudioToggle.state = Prefs.storeAudio ? .on : .off
        retentionField.integerValue = Prefs.retentionDays
    }

    private var keyFieldValue: String {
        (showKeyToggle.state == .on ? plainKeyField.stringValue : secureKeyField.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            keyStatusLabel.stringValue = "Поле пустое"
            return
        }
        if Keychain.save(key) {
            keyStatusLabel.stringValue = "Сохранено в Keychain"
        } else {
            keyStatusLabel.stringValue = "Не удалось сохранить"
        }
    }

    @objc private func testKey() {
        let key = keyFieldValue
        guard !key.isEmpty else {
            keyStatusLabel.stringValue = "Поле пустое"
            return
        }
        keyStatusLabel.stringValue = "Проверяю…"
        GroqClient.validateKey(key) { [weak self] problem in
            DispatchQueue.main.async {
                self?.keyStatusLabel.stringValue = (problem == nil) ? "✓ Ключ рабочий" : "✗ \(problem!)"
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

    @objc private func storeAudioChanged() {
        Prefs.storeAudio = (storeAudioToggle.state == .on)
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
        alert.messageText = "Удалить все данные?"
        alert.informativeText = """
            Будут безвозвратно удалены:
            • \(counts.records) транскрибаций
            • \(counts.audioFiles) аудиофайлов
            • API-ключ из Keychain
            • все настройки

            Для подтверждения введите ниже:
            \(phrase)
            """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Удалить всё")
        alert.addButton(withTitle: "Отмена")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard field.stringValue.trimmingCharacters(in: .whitespaces) == phrase else {
            let mismatch = NSAlert()
            mismatch.messageText = "Фраза не совпала"
            mismatch.informativeText = "Удаление отменено. Ничего не тронуто."
            mismatch.runModal()
            return
        }

        Store.shared.deleteAll()
        Keychain.delete()
        Prefs.reset()
        populate()
        onHotkeySettingsChanged?()

        let done = NSAlert()
        done.messageText = "Готово"
        done.informativeText = "Все данные удалены."
        done.runModal()
    }
}
