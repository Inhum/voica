// Окно настроек: вкладки в стиле системных настроек macOS (toolbar-style, как Tailscale).
// General — ключ Groq и обновления; Dictation — режим/клавиша/вывод;
// Vocabulary — словарь и ИИ-исправление (с проверкой доступности модели);
// Data — аудио и полное удаление данных (с подтверждением случайной фразой).

import Cocoa

final class SettingsWindowController: NSWindowController, NSTextViewDelegate, NSWindowDelegate {
    /// Вызывается после изменения настроек хоткея, чтобы применить их вживую.
    var onHotkeySettingsChanged: (() -> Void)?

    // General: движок распознавания
    private var engineControl: NSSegmentedControl!
    private var engineStatusIcon: NSImageView!
    private var engineStatusLabel: NSTextField!
    private var engineProgress: NSProgressIndicator!
    private var engineCancelBtn: NSButton!

    // General
    private var secureKeyField: NSSecureTextField!
    private var plainKeyField: NSTextField!
    private var showKeyToggle: NSButton!
    private var keyStatusLabel: NSTextField!
    private var noKeyHint: NSTextField!
    private var statusIcon: NSImageView!
    private var statusSpinner: NSProgressIndicator!
    private var checkUpdatesToggle: NSButton!
    // About — проверка обновлений в самой вкладке
    private var updateCheckBtn: NSButton!
    private var updateSpinner: NSProgressIndicator!
    private var updateStatusLabel: NSTextField!
    private var updateDownloadBtn: NSButton!
    private var pendingUpdateURL: URL?

    // Dictation
    private var modeControl: NSSegmentedControl!
    private var outputControl: NSSegmentedControl!
    private var keyPopup: NSPopUpButton!
    private var sttModelPopup: NSPopUpButton!
    private var sttLanguagePopup: NSPopUpButton!
    private var recordingHUDToggle: NSButton!
    private var doubleTapToggle: NSButton!
    private var fillersToggle: NSButton!
    private var quotesToggle: NSButton!
    private var proxyToggle: NSButton!
    private var engineDownloadBtn: NSButton!
    private var llmStatusRow: NSStackView!
    private var termRulesToggle: NSButton!

    // Vocabulary
    private var vocabTextView: NSTextView!
    private var vocabCounter: NSTextField!
    private var llmToggle: NSButton!
    private var llmStatusLabel: NSTextField!
    private var llmStatusIcon: NSImageView!
    private var llmSpinner: NSProgressIndicator!
    private var chatModelPopup: NSPopUpButton!
    private var chatModelRow: NSStackView!

    // Data
    private var storeAudioToggle: NSButton!
    private var retentionField: NSTextField!
    private var deleteModelBtn: NSButton!
    private var modelSizeLabel: NSTextField!

    private var tabs: FittingTabViewController!

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
        tabs = FittingTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false   // держим общий заголовок окна
        tabs.onSelectionChanged = { [weak self] in self?.fitWindowToSelectedTab() }

        addTab(L("settings.tab.general"),   symbol: "gearshape",             view: buildGeneralTab())
        addTab(L("settings.tab.dictation"), symbol: "mic",                   view: buildDictationTab())
        addTab(L("settings.tab.vocab"),     symbol: "character.book.closed", view: buildVocabularyTab())
        addTab(L("settings.tab.data"),      symbol: "internaldrive",         view: buildDataTab())
        addTab(L("settings.tab.network"),   symbol: "network",               view: buildNetworkTab())
        addTab(L("settings.tab.about"),     symbol: "info.circle",           view: buildAboutTab())

        window?.contentViewController = tabs
    }

    /// Ширина вкладки. Одна на все — окно должно менять высоту под содержимое, но НЕ ширину:
    /// иначе оно скачет при переключении табов, а места по горизонтали и так хватает.
    private static let tabWidth: CGFloat = 460

    private func addTab(_ label: String, symbol: String, view: NSView) {
        let vc = NSViewController()
        vc.view = view
        view.layoutSubtreeIfNeeded()
        // Берём только высоту. `fittingSize` содержит и ширину, а она у вкладок расходится
        // (самая широкая — Dictation), и окно прыгало по горизонтали при каждом переключении.
        vc.preferredContentSize = NSSize(width: Self.tabWidth, height: view.fittingSize.height)
        let item = NSTabViewItem(viewController: vc)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        tabs.addTabViewItem(item)
    }

    /// Контейнер вкладки: вертикальный стек с полями 18pt, ширина контента 424.
    private func tabContainer() -> (NSView, NSStackView) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: Self.tabWidth).isActive = true
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

        // Движок распознавания: облако / локально (+докачка модели с прогрессом)
        stack.addArrangedSubview(header(L("settings.engine.header")))

        engineControl = NSSegmentedControl(labels: [L("settings.engine.cloud"), L("settings.engine.local")],
                                           trackingMode: .selectOne, target: self,
                                           action: #selector(engineChanged))
        stack.addArrangedSubview(engineControl)

        engineStatusIcon = makeStatusIcon()
        engineStatusLabel = makeStatusLabel()
        engineProgress = NSProgressIndicator()
        engineProgress.style = .bar
        engineProgress.isIndeterminate = false
        engineProgress.minValue = 0
        engineProgress.maxValue = 1
        engineProgress.translatesAutoresizingMaskIntoConstraints = false
        engineProgress.widthAnchor.constraint(equalToConstant: 160).isActive = true
        engineProgress.isHidden = true
        engineCancelBtn = NSButton(title: L("settings.engine.cancel"), target: self,
                                   action: #selector(cancelModelDownload))
        engineCancelBtn.controlSize = .small
        engineCancelBtn.isHidden = true
        // ⚠️ Скачивание больше НЕ стартует само при выборе локального движка (§9.5): в сети
        // с прокси-авторизацией это мгновенный 407, которого человек не просил. Теперь это
        // явное действие, и видно, что сейчас начнётся загрузка на сотни мегабайт.
        engineDownloadBtn = NSButton(title: L("settings.engine.download"), target: self,
                                     action: #selector(startModelDownload))
        engineDownloadBtn.controlSize = .small
        engineDownloadBtn.isHidden = true

        let engineStatusRow = NSStackView(views: [engineStatusIcon, engineStatusLabel,
                                                  engineProgress, engineCancelBtn,
                                                  engineDownloadBtn])
        engineStatusRow.spacing = 6
        engineStatusRow.alignment = .centerY
        stack.addArrangedSubview(engineStatusRow)

        stack.addArrangedSubview(makeHint(L("settings.engine.hint")))

        // Скачивание — процесс долгий и переживает закрытие окна; подписываемся один раз.
        ModelDownloader.shared.onProgress = { [weak self] p in
            guard let self else { return }
            self.engineProgress.doubleValue = p
            self.engineStatusLabel.stringValue = L("settings.engine.status.downloading", Int(p * 100))
        }
        ModelDownloader.shared.onFinish = { [weak self] outcome in
            self?.modelDownloadFinished(outcome)
        }

        stack.addArrangedSubview(separator())

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

        // Выход из тупика первого запуска: ключа нет, поле открыто, и человек решает, что без
        // ключа приложение бесполезно. Строка стоит там, куда смотрит глаз — под полем ключа,
        // а не выше у переключателя движка. Цвет обычный, не блёклый: среди трёх серых
        // подсказок на этой вкладке она бы потерялась, и весь смысл пропал бы.
        noKeyHint = makeHint(L("settings.key.nokey"))
        noKeyHint.textColor = .labelColor
        stack.addArrangedSubview(noKeyHint)

        let hint = makeHint(L("settings.key.hint"))
        stack.addArrangedSubview(hint)

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
        // Компактный чекбокс «двойной тап» справа от выбора клавиши; пояснение — в ⓘ (по наведению).
        doubleTapToggle = NSButton(checkboxWithTitle: L("settings.rec.doubletap"),
                                   target: self, action: #selector(doubleTapChanged))
        let keyRow = labeledRow(L("settings.keyChoice.label"), keyPopup)
        keyRow.setCustomSpacing(20, after: keyPopup)   // отодвинуть чекбокс правее от попапа
        keyRow.addArrangedSubview(doubleTapToggle)
        keyRow.addArrangedSubview(InfoDot(L("settings.rec.doubletap.hint")))
        stack.addArrangedSubview(keyRow)

        outputControl = NSSegmentedControl(labels: [L("settings.output.insert"), L("settings.output.window")],
                                           trackingMode: .selectOne, target: self,
                                           action: #selector(outputChanged))
        stack.addArrangedSubview(labeledRow(L("settings.output.label"), outputControl))

        stack.addArrangedSubview(makeHint(L("settings.output.hint")))

        recordingHUDToggle = NSButton(checkboxWithTitle: L("settings.rec.hud"),
                                      target: self, action: #selector(recordingHUDChanged))
        let hudRow = NSStackView(views: [recordingHUDToggle, InfoDot(L("settings.rec.hud.hint"))])
        hudRow.spacing = 6
        hudRow.alignment = .centerY
        stack.addArrangedSubview(hudRow)

        stack.addArrangedSubview(separator())

        // Облачное распознавание: модель (Turbo/Large v3) и язык. Только облако — локальный
        // движок один (GigaAM, русский). Значения — представленные объекты пунктов.
        stack.addArrangedSubview(header(L("settings.stt.header")))

        sttModelPopup = NSPopUpButton()
        for (title, id) in [(L("settings.stt.model.turbo"), "whisper-large-v3-turbo"),
                            (L("settings.stt.model.large"), "whisper-large-v3")] {
            sttModelPopup.addItem(withTitle: title)
            sttModelPopup.lastItem?.representedObject = id
        }
        sttModelPopup.target = self
        sttModelPopup.action = #selector(sttModelChanged)
        stack.addArrangedSubview(labeledRow(L("settings.stt.model"), sttModelPopup))

        sttLanguagePopup = NSPopUpButton()
        for (title, code) in [(L("settings.stt.language.auto"), "auto"),
                              (L("settings.stt.language.ru"), "ru"),
                              (L("settings.stt.language.en"), "en")] {
            sttLanguagePopup.addItem(withTitle: title)
            sttLanguagePopup.lastItem?.representedObject = code
        }
        sttLanguagePopup.target = self
        sttLanguagePopup.action = #selector(sttLanguageChanged)
        stack.addArrangedSubview(labeledRow(L("settings.stt.language"), sttLanguagePopup))

        // Подсказка ушла в точку «ⓘ»: вкладка и так самая высокая, а с двумя абзацами текста
        // нижние элементы переставали помещаться в окно.
        stack.addArrangedSubview(NSStackView(views: [
            makeShortHint(L("settings.stt.short")), InfoDot(L("settings.stt.hint")),
        ]))

        stack.addArrangedSubview(header(L("settings.cleanup.header")))
        fillersToggle = NSButton(checkboxWithTitle: L("settings.fillers.toggle"),
                                 target: self, action: #selector(fillersChanged))
        stack.addArrangedSubview(NSStackView(views: [
            fillersToggle, InfoDot(L("settings.fillers.hint")),
        ]))
        quotesToggle = NSButton(checkboxWithTitle: L("settings.quotes.toggle"),
                                target: self, action: #selector(quotesChanged))
        stack.addArrangedSubview(NSStackView(views: [
            quotesToggle, InfoDot(L("settings.quotes.hint")),
        ]))

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

        termRulesToggle = NSButton(checkboxWithTitle: L("settings.vocab.rules"),
                                   target: self, action: #selector(termRulesChanged))
        stack.addArrangedSubview(termRulesToggle)
        // Здесь подсказка в потоке, а не в точке «ⓘ»: на этой вкладке так оформлены все
        // остальные, и высоты хватает — в отличие от Dictation, где она и переполнялась.
        stack.addArrangedSubview(makeHint(L("settings.vocab.rules.hint")))

        llmToggle = NSButton(checkboxWithTitle: L("settings.vocab.llm"),
                             target: self, action: #selector(llmChanged))
        stack.addArrangedSubview(llmToggle)

        llmSpinner = makeSpinner()
        llmStatusIcon = makeStatusIcon()
        llmStatusLabel = makeStatusLabel()
        // Статус может быть длинным (напр. «Model … is blocked — allow it at …») — переносим
        // по словам, а не обрезаем. Иконку/спиннер прижимаем к первой строке.
        llmStatusLabel.lineBreakMode = .byWordWrapping
        llmStatusLabel.maximumNumberOfLines = 0
        llmStatusLabel.cell?.wraps = true
        llmStatusLabel.cell?.isScrollable = false
        llmStatusLabel.preferredMaxLayoutWidth = 400
        llmStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
        let statusRow = NSStackView(views: [llmSpinner, llmStatusIcon, llmStatusLabel])
        statusRow.spacing = 6
        statusRow.alignment = .top
        // Пустая строка статуса всё равно занимала высоту, и при выключенном ИИ-проходе внизу
        // вкладки зияла дыра. Прячем её вместе с выбором модели.
        statusRow.isHidden = true
        llmStatusRow = statusRow
        stack.addArrangedSubview(statusRow)

        // Выбор chat-модели: «Рекомендуемая (автоматически)» + живой список (power-user).
        chatModelPopup = NSPopUpButton()
        chatModelPopup.target = self
        chatModelPopup.action = #selector(chatModelChanged)
        chatModelRow = labeledRow(L("settings.vocab.llm.model"), chatModelPopup)
        chatModelRow.isHidden = true   // показываем только когда ИИ-исправление включено
        stack.addArrangedSubview(chatModelRow)

        stack.addArrangedSubview(makeHint(L("settings.vocab.llm.hint")))

        return container
    }

    // MARK: - Вкладка Data (аудио + удаление)

    /// Вкладка Network (§11.4). Пока одна настройка — системный прокси; ручной прокси, если
    /// понадобится, ляжет сюда же (§9.5).
    private func buildNetworkTab() -> NSView {
        let (container, stack) = tabContainer()
        stack.addArrangedSubview(header(L("settings.network.header")))
        proxyToggle = NSButton(checkboxWithTitle: L("settings.proxy.toggle"),
                               target: self, action: #selector(proxyChanged))
        stack.addArrangedSubview(proxyToggle)
        stack.addArrangedSubview(makeHint(L("settings.proxy.hint")))
        return container
    }

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

        // Локальная модель: сколько занимает на диске + удаление (вместе с кэшем)
        stack.addArrangedSubview(header(L("settings.model.header")))
        modelSizeLabel = makeStatusLabel()
        deleteModelBtn = NSButton(title: L("settings.model.delete"), target: self,
                                  action: #selector(deleteLocalModel))
        let modelRow = NSStackView(views: [deleteModelBtn, modelSizeLabel])
        modelRow.spacing = 8
        modelRow.alignment = .centerY
        stack.addArrangedSubview(modelRow)
        stack.addArrangedSubview(makeHint(L("settings.model.hint")))

        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(header(L("settings.data.header")))
        let deleteBtn = NSButton(title: L("settings.data.deleteAll"), target: self, action: #selector(deleteAllData))
        deleteBtn.hasDestructiveAction = true
        stack.addArrangedSubview(deleteBtn)

        return container
    }

    // MARK: - Вкладка About (о программе + обновления)

    private func buildAboutTab() -> NSView {
        let (container, stack) = tabContainer()

        // Шапка: иконка приложения + имя/версия (компоновка как в Windows-версии)
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let name = NSTextField(labelWithString: "Voica")
        name.font = .boldSystemFont(ofSize: 20)
        let ver = NSTextField(labelWithString: L("about.version", appVersion))
        ver.textColor = .secondaryLabelColor
        let nameCol = NSStackView(views: [name, ver])
        nameCol.orientation = .vertical
        nameCol.alignment = .leading
        nameCol.spacing = 2
        let headRow = NSStackView(views: [icon, nameCol])
        headRow.spacing = 14
        headRow.alignment = .centerY
        stack.addArrangedSubview(headRow)

        stack.addArrangedSubview(aboutText(L("about.tagline"), size: 12, color: .labelColor))
        stack.addArrangedSubview(aboutText(L("about.privacy"), size: 11, color: .secondaryLabelColor))

        stack.addArrangedSubview(separator())

        // Обновления: проверка прямо здесь + авто-проверка при запуске (переехало из General)
        stack.addArrangedSubview(header(L("settings.updates.header")))
        updateCheckBtn = NSButton(title: L("about.checkNow"), target: self, action: #selector(checkUpdatesNow))
        updateSpinner = makeSpinner()
        updateStatusLabel = makeStatusLabel()
        let updRow = NSStackView(views: [updateCheckBtn, updateSpinner, updateStatusLabel])
        updRow.spacing = 8
        updRow.alignment = .centerY
        stack.addArrangedSubview(updRow)

        updateDownloadBtn = NSButton(title: L("about.download"), target: self, action: #selector(openUpdatePage))
        updateDownloadBtn.isHidden = true
        stack.addArrangedSubview(updateDownloadBtn)

        checkUpdatesToggle = NSButton(checkboxWithTitle: L("settings.updates.onLaunch"),
                                      target: self, action: #selector(checkUpdatesChanged))
        stack.addArrangedSubview(checkUpdatesToggle)

        stack.addArrangedSubview(separator())

        // Ссылки + лицензия. Поддержка — донат, приложение остаётся бесплатным целиком:
        // подписки и платных функций нет, поэтому кнопка стоит рядом с GitHub, а не выше.
        let gh = NSButton(title: L("about.github"), target: self, action: #selector(openGitHubRepo))
        gh.bezelStyle = .rounded
        let support = NSButton(title: L("about.support"), target: self, action: #selector(openSupportPage))
        support.bezelStyle = .rounded
        let linksRow = NSStackView(views: [gh, support])
        linksRow.spacing = 8
        linksRow.alignment = .centerY
        stack.addArrangedSubview(linksRow)

        stack.addArrangedSubview(aboutText(L("about.support.hint"), size: 11, color: .secondaryLabelColor))

        let lic = NSTextField(labelWithString: "© 2026 Ivan Ushakov · MIT License")
        lic.textColor = .tertiaryLabelColor
        lic.font = .systemFont(ofSize: 10)
        stack.addArrangedSubview(lic)

        return container
    }

    /// Переносимый абзац текста в About (ширина под контент вкладки).
    private func aboutText(_ s: String, size: CGFloat, color: NSColor) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: size)
        t.textColor = color
        t.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return t
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

    /// Короткая подпись для ряда с точкой «ⓘ»: ширина по содержимому, как у чекбокса.
    ///
    /// `makeHint` для этого не годится: он делает переносящуюся по словам подпись, а такой
    /// нужна ЗАДАННАЯ ширина — иначе непонятно, где переносить. Из-за этого точка вставала
    /// после коробки в 424 пункта, то есть у правого края окна, а не после текста.
    private func makeShortHint(_ text: String) -> NSTextField {
        let hint = NSTextField(labelWithString: text)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        return hint
    }

    private func makeHint(_ text: String, width: CGFloat = 424) -> NSTextField {
        // Подстрочные пояснения: 11pt + secondaryLabel — читаемо, как в системных
        // настройках и Tailscale (10pt/tertiary были слишком мелкими и блёклыми).
        let hint = NSTextField(wrappingLabelWithString: text)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        // Ширина задаётся явно, иначе перенос по словам не работает. Для подсказки, стоящей
        // рядом с точкой «ⓘ», её надо уменьшить: иначе ряд не влезает в 424 пункта содержимого,
        // точка уезжает за край, а окно расширяется под неё — вкладки становятся разной ширины.
        hint.widthAnchor.constraint(equalToConstant: width).isActive = true
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
        setStatusIcon(icon, kind)
    }

    private func setStatusIcon(_ icon: NSImageView, _ kind: StatusKind) {
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
        fitWindowToSelectedTab()
        window?.makeFirstResponder(secureKeyField)
    }

    func show() {
        populate()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        fitWindowToSelectedTab()
    }

    /// Открыть настройки сразу на вкладке General — туда ведёт кнопка из предупреждения
    /// о неустановленной локальной модели: там и переключатель движка, и кнопка «Скачать».
    func showGeneral() { showOn(tab: 0) }

    /// Открыть настройки сразу на вкладке About (пункт меню-бара «О Voica» ведёт сюда).
    func showAbout() { showOn(tab: tabs.tabViewItems.count - 1) }   // About — последняя

    private func showOn(tab index: Int) {
        populate()
        tabs.selectedTabViewItemIndex = index
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        fitWindowToSelectedTab()
    }

    /// Подогнать высоту окна под выбранную вкладку.
    ///
    /// Штатной подгонки не хватает в двух местах: на первом показе (вкладку выбрали до того, как
    /// окно появилось на экране — так открывается «О программе») и при уходе на более низкую
    /// вкладку (окно растёт, но обратно не ужимается). Через `preferredContentSize` это не
    /// лечится: значение к моменту показа уже равно нужному, присвоение того же самого ничего не
    /// меняет и окно остаётся как было. Поэтому двигаем рамку сами — на разницу между тем, что
    /// вкладке нужно, и тем, сколько она занимает сейчас. Верхний край окна держим на месте:
    /// иначе оно «прыгает» вниз при каждом переключении.
    private func fitWindowToSelectedTab() {
        let idx = tabs.selectedTabViewItemIndex
        guard let window,
              tabs.tabViewItems.indices.contains(idx),
              let vc = tabs.tabViewItems[idx].viewController else { return }
        let delta = vc.preferredContentSize.height - tabs.view.frame.height
        guard abs(delta) > 0.5 else { return }
        var frame = window.frame
        frame.size.height += delta
        frame.origin.y -= delta
        // Ширину задаём ЖЁСТКО, а не «не трогаем»: одного `preferredContentSize` мало —
        // NSTabViewController всё равно подгоняет окно под фактическую ширину вкладки, и она
        // у Dictation больше. Окно от этого прыгало по горизонтали при каждом переключении,
        // хотя места и так хватает. Меняться должна только высота.
        frame.size.width = window.frameRect(forContentRect:
            NSRect(x: 0, y: 0, width: Self.tabWidth, height: 0)).width
        window.setFrame(frame, display: true)
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
        selectByRepresented(sttModelPopup, Prefs.sttModel)
        selectByRepresented(sttLanguagePopup, Prefs.sttLanguage)
        recordingHUDToggle.state = Prefs.recordingHUD ? .on : .off
        doubleTapToggle.state = Prefs.toggleDoubleTap ? .on : .off
        proxyToggle.state = Prefs.useSystemProxy ? .on : .off
        fillersToggle.state = Prefs.stripFillers ? .on : .off
        quotesToggle.state = Prefs.fixQuotes ? .on : .off
        termRulesToggle.state = Prefs.fixTermsByRules ? .on : .off
        storeAudioToggle.state = Prefs.storeAudio ? .on : .off
        retentionField.integerValue = Prefs.retentionDays
        checkUpdatesToggle.state = Prefs.checkUpdatesOnLaunch ? .on : .off
        updateStatusLabel.stringValue = ""
        updateDownloadBtn.isHidden = true
        updateCheckBtn.isEnabled = true
        updateSpinner.stopAnimation(nil)
        pendingUpdateURL = nil
        vocabTextView.string = Prefs.vocabulary
        updateVocabCounter()
        llmToggle.state = Prefs.llmPostProcess ? .on : .off
        if Prefs.llmPostProcess { verifyChatModel() } else { clearLLMStatus() }
        refreshEngineUI()
        refreshModelSizeUI()
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
            refreshNoKeyHint()          // ключ появился — подсказка про локальный движок не нужна
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

    @objc private func sttModelChanged() {
        Prefs.sttModel = (sttModelPopup.selectedItem?.representedObject as? String) ?? GroqClient.defaultSTTModel
        // Строка «Работает модель…» живёт на вкладке General, а выбор — здесь; без обновления
        // она показывала бы прежнюю модель до следующего открытия настроек.
        refreshEngineUI()
    }

    @objc private func sttLanguageChanged() {
        Prefs.sttLanguage = (sttLanguagePopup.selectedItem?.representedObject as? String) ?? "auto"
    }

    @objc private func recordingHUDChanged() {
        Prefs.recordingHUD = (recordingHUDToggle.state == .on)
    }

    @objc private func fillersChanged() {
        Prefs.stripFillers = (fillersToggle.state == .on)
    }

    @objc private func quotesChanged() {
        Prefs.fixQuotes = (quotesToggle.state == .on)
    }

    @objc private func termRulesChanged() {
        Prefs.fixTermsByRules = (termRulesToggle.state == .on)
    }

    @objc private func doubleTapChanged() {
        Prefs.toggleDoubleTap = (doubleTapToggle.state == .on)
    }

    /// Выбирает в поповере пункт с заданным representedObject (фолбэк — первый).
    private func selectByRepresented(_ popup: NSPopUpButton, _ value: String) {
        let idx = popup.itemArray.firstIndex { ($0.representedObject as? String) == value }
        popup.selectItem(at: idx ?? 0)
    }

    @objc private func storeAudioChanged() {
        Prefs.storeAudio = (storeAudioToggle.state == .on)
    }

    @objc private func checkUpdatesChanged() {
        Prefs.checkUpdatesOnLaunch = (checkUpdatesToggle.state == .on)
    }

    @objc private func openGitHubRepo() {
        if let url = URL(string: "https://github.com/Inhum/voica") { NSWorkspace.shared.open(url) }
    }

    @objc private func openSupportPage() {
        if let url = URL(string: "https://boosty.to/voica") { NSWorkspace.shared.open(url) }
    }

    @objc private func openUpdatePage() {
        if let url = pendingUpdateURL { NSWorkspace.shared.open(url) }
    }

    /// Ручная проверка обновлений из вкладки About: статус прямо здесь, кнопка «Скачать» при
    /// наличии новой версии (ведёт на страницу релиза — как и пункт меню-бара).
    @objc private func checkUpdatesNow() {
        updateCheckBtn.isEnabled = false
        updateDownloadBtn.isHidden = true
        pendingUpdateURL = nil
        updateSpinner.startAnimation(nil)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.stringValue = L("about.checking")
        Updater.check { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateSpinner.stopAnimation(nil)
                self.updateCheckBtn.isEnabled = true
                switch result {
                case .success(let update?):
                    self.pendingUpdateURL = update.pageURL
                    self.updateDownloadBtn.isHidden = false
                    self.updateStatusLabel.textColor = .controlAccentColor
                    self.updateStatusLabel.stringValue = L("about.updateAvail", update.version)
                case .success(nil):
                    self.updateStatusLabel.textColor = .secondaryLabelColor
                    self.updateStatusLabel.stringValue = L("about.upToDate", appVersion)
                case .failure(let err):
                    self.updateStatusLabel.textColor = .systemOrange
                    self.updateStatusLabel.stringValue = L("about.checkFailed", err.localizedDescription)
                }
            }
        }
    }

    @objc private func retentionChanged() {
        Prefs.retentionDays = max(0, retentionField.integerValue)
        retentionField.integerValue = Prefs.retentionDays
    }

    // MARK: - Действия: движок распознавания / локальная модель

    @objc private func engineChanged() {
        let local = (engineControl.selectedSegment == 1)
        Prefs.sttEngine = local ? "local" : "cloud"
        if !local, ModelDownloader.shared.isDownloading {
            ModelDownloader.shared.cancel()   // передумали — не тратим трафик
        }
        refreshEngineUI()
    }

    @objc private func startModelDownload() {
        guard !ModelDownloader.shared.isDownloading, !LocalSTT.isModelAvailable else { return }
        engineProgress.doubleValue = 0
        ModelDownloader.shared.start()
        refreshEngineUI()
    }

    @objc private func proxyChanged() {
        Prefs.useSystemProxy = (proxyToggle.state == .on)
        // Конфигурация читается при создании сессии — без пересоздания настройка не подействует
        // до перезапуска приложения.
        HTTP.reloadSession()
    }

    @objc private func cancelModelDownload() {
        ModelDownloader.shared.cancel()
    }

    private func modelDownloadFinished(_ outcome: ModelDownloader.Outcome) {
        // Если модель не появилась (отмена/ошибка) — честно возвращаемся на облако.
        if !LocalSTT.isModelAvailable, Prefs.sttEngine == "local" {
            Prefs.sttEngine = "cloud"
        }
        refreshEngineUI()
        refreshModelSizeUI()
        if case .failure(let msg) = outcome {
            engineStatusLabel.stringValue = L("settings.engine.status.failed", msg)
            setStatusIcon(engineStatusIcon, .warning)
        }
    }

    /// Строка про локальный движок нужна ровно в одной ситуации: выбрано облако и ключа нет.
    /// Есть ключ — облако работает; выбран локальный — ключ и не требуется.
    private func refreshNoKeyHint() {
        noKeyHint?.isHidden = !(Prefs.sttEngine == "cloud" && KeyStore.load() == nil)
    }

    private func refreshEngineUI() {
        refreshNoKeyHint()
        engineControl.selectedSegment = (Prefs.sttEngine == "local") ? 1 : 0
        refreshNoKeyHint()
        let downloading = ModelDownloader.shared.isDownloading
        engineProgress.isHidden = !downloading
        engineCancelBtn.isHidden = !downloading
        // «Скачать» видна ровно там, где модели нет и она нужна.
        engineDownloadBtn?.isHidden = !(Prefs.sttEngine == "local" && !LocalSTT.isModelAvailable
                                        && !downloading)
        // Статус называет РАБОТАЮЩУЮ модель, а не только факт установки локальной.
        if downloading {
            engineStatusLabel.stringValue =
                L("settings.engine.status.downloading", Int(engineProgress.doubleValue * 100))
            setStatusIcon(engineStatusIcon, .neutral)
        } else if Prefs.sttEngine == "local", LocalSTT.isModelAvailable {
            engineStatusLabel.stringValue = L("settings.engine.status.localActive")
            setStatusIcon(engineStatusIcon, .success)
        } else if Prefs.sttEngine == "local" {
            engineStatusLabel.stringValue = L("settings.engine.status.missing")
            setStatusIcon(engineStatusIcon, .neutral)
        } else {
            // ⚠️ Имя модели ПОДСТАВЛЯЕТСЯ, а не зашито в строку. Зашитое врало: строка называла
            // whisper-large-v3-turbo, когда в настройках выбран whisper-large-v3, — поймано на
            // скриншоте пользователя. Строка про активную модель обязана читать настройку.
            engineStatusLabel.stringValue = String(format: L("settings.engine.status.cloudActive"),
                                                   Prefs.sttModel)
            setStatusIcon(engineStatusIcon, .success)
        }
    }

    private func refreshModelSizeUI() {
        let bytes = ModelDownloader.installedSizeBytes()
        if bytes > 0 {
            deleteModelBtn.isEnabled = true
            modelSizeLabel.stringValue = L("settings.model.size",
                ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        } else {
            deleteModelBtn.isEnabled = false
            modelSizeLabel.stringValue = L("settings.model.none")
        }
    }

    @objc private func deleteLocalModel() {
        let size = ByteCountFormatter.string(fromByteCount: ModelDownloader.installedSizeBytes(),
                                             countStyle: .file)
        let alert = NSAlert()
        alert.messageText = L("settings.model.delete.title")
        alert.informativeText = L("settings.model.delete.msg", size)
        alert.addButton(withTitle: L("settings.model.delete.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ModelDownloader.deleteInstalledModel()
        if Prefs.sttEngine == "local" { Prefs.sttEngine = "cloud" }
        refreshEngineUI()
        refreshModelSizeUI()
    }

    // MARK: - Действия: ИИ-исправление (verify доступности модели)

    @objc private func llmChanged() {
        Prefs.llmPostProcess = (llmToggle.state == .on)
        if Prefs.llmPostProcess { verifyChatModel() } else { clearLLMStatus() }
    }

    /// Пользователь выбрал модель в поповере: сохраняем и перепроверяем (резолв + проба на 403).
    @objc private func chatModelChanged() {
        Prefs.chatModel = (chatModelPopup.selectedItem?.representedObject as? String) ?? "auto"
        verifyChatModel()
    }

    private func verifyChatModel() {
        chatModelRow.isHidden = false
        llmStatusRow.isHidden = false
        llmStatusIcon.isHidden = true
        llmStatusLabel.stringValue = L("settings.vocab.llm.checking")
        llmSpinner.startAnimation(nil)
        GroqClient.verifyChatModel { [weak self] state, live in
            DispatchQueue.main.async {
                guard let self else { return }
                self.populateChatModelPopup(live)
                let text: String
                let kind: StatusKind
                switch state {
                case .available(let m): text = L("settings.vocab.llm.using", m);     kind = .success
                case .switched(let m):  text = L("settings.vocab.llm.switched", m);   kind = .success
                case .blocked(let m):   text = L("settings.vocab.llm.blocked", m);    kind = .warning
                case .unavailable:      text = L("settings.vocab.llm.unavailable");   kind = .warning
                case .error(let e):     text = e;                                     kind = .warning
                }
                self.applyStatus(icon: self.llmStatusIcon, spinner: self.llmSpinner,
                                 label: self.llmStatusLabel, text: text, kind: kind)
            }
        }
    }

    /// Наполняет поповер: «Рекомендуемая (автоматически)» + живой список. Если список не
    /// получен (офлайн) — оставляем «авто» (+ текущий ручной выбор, чтобы отражал реальность).
    private func populateChatModelPopup(_ live: [String]?) {
        chatModelPopup.removeAllItems()
        chatModelPopup.addItem(withTitle: L("settings.vocab.llm.model.auto"))
        chatModelPopup.lastItem?.representedObject = "auto"

        var ids = live ?? []
        let choice = Prefs.chatModel
        if choice != "auto", !ids.contains(choice) { ids.insert(choice, at: 0) }
        if !ids.isEmpty {
            chatModelPopup.menu?.addItem(.separator())
            for id in ids {
                chatModelPopup.addItem(withTitle: id)
                chatModelPopup.lastItem?.representedObject = id
            }
        }
        chatModelPopup.isEnabled = (live != nil)

        let idx = chatModelPopup.itemArray.firstIndex { ($0.representedObject as? String) == choice }
        chatModelPopup.selectItem(at: idx ?? 0)
    }

    private func clearLLMStatus() {
        llmSpinner.stopAnimation(nil)
        llmStatusIcon.isHidden = true
        llmStatusLabel.stringValue = ""
        chatModelRow.isHidden = true
        llmStatusRow.isHidden = true
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

/// Вкладки, сообщающие наружу о смене выбора, — чтобы окно можно было подогнать под вкладку.
/// Штатный NSTabViewController увеличивает окно под более высокую вкладку, но обратно не
/// ужимает: без этого окно остаётся высотой самой высокой из уже открытых.
final class FittingTabViewController: NSTabViewController {
    var onSelectionChanged: (() -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        onSelectionChanged?()
    }
}
