// Окно История: список транскрибаций слева, подробности справа.
// Действия: копировать текст, проиграть аудио (если хранится), удалить запись.

import Cocoa
import AVFoundation

final class HistoryWindowController: NSWindowController {
    /// Весь список из базы. `records` — то, что показано после фильтра поиска.
    private var allRecords: [TranscriptRecord] = []
    private var records: [TranscriptRecord] = []
    private var searchField: NSSearchField!
    /// Сводка поиска — на уровне поля поиска, над текстом записи. В нижней строке ей тесно:
    /// там метаданные записи, и при узком окне обрезается то одно, то другое.
    private var searchInfo: NSTextField!
    private var tableView: NSTableView!
    private var detailText: NSTextView!
    private var infoLabel: NSTextField!
    private var copyButton: NSButton!
    private var playButton: NSButton!
    private var deleteButton: NSButton!
    private var exportButton: NSButton!
    private var emptyLabel: NSTextField!
    private var exportPanel: NSSavePanel?
    private var exportPopup: NSPopUpButton?
    private var player: AVAudioPlayer?
    private var resetCopyWork: DispatchWorkItem?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    convenience init() {
        let window = HistoryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = L("history.title")
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("voica-main")
        window.minSize = NSSize(width: 600, height: 320)
        self.init(window: window)
        buildUI()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Поиск над списком: записей копятся тысячи, скролл перестаёт быть навигацией.
        let search = NSSearchField()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholderString = L("history.search")
        search.sendsSearchStringImmediately = false   // фильтруем по паузе, не по каждой букве
        search.target = self
        search.action = #selector(searchChanged)
        content.addSubview(search)
        searchField = search

        // Список слева
        let listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder

        let table = HistoryTableView()
        table.headerView = nil
        table.rowHeight = 50
        table.usesAutomaticRowHeights = false
        // Мультивыделение: Cmd/Shift/Cmd+A начинают работать сами, обрабатывать их не нужно.
        table.allowsMultipleSelection = true
        table.onDeleteKey = { [weak self] in self?.deleteSelected() }
        table.menu = {
            let m = NSMenu()
            m.addItem(NSMenuItem(title: L("history.delete"), action: #selector(deleteSelected), keyEquivalent: ""))
            m.items.forEach { $0.target = self }
            return m
        }()
        let col = NSTableColumn(identifier: .init("entry"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.target = self
        listScroll.documentView = table
        tableView = table
        content.addSubview(listScroll)

        searchInfo = NSTextField(labelWithString: "")
        searchInfo.translatesAutoresizingMaskIntoConstraints = false
        searchInfo.textColor = .secondaryLabelColor
        searchInfo.font = .systemFont(ofSize: 11)
        searchInfo.lineBreakMode = .byTruncatingTail
        content.addSubview(searchInfo)

        // Детали справа
        let detailScroll = NSScrollView()
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.autoresizingMask = [.width]
        detailScroll.documentView = tv
        detailText = tv
        content.addSubview(detailScroll)

        infoLabel = NSTextField(labelWithString: "")
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.lineBreakMode = .byTruncatingTail    // при узком окне усечь, а не лезть под кнопки
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.addSubview(infoLabel)

        copyButton = makeButton(L("result.copy"), symbol: "doc.on.doc", action: #selector(copyText))
        playButton = makeButton(L("history.play"), symbol: "play.fill", action: #selector(togglePlay))
        deleteButton = makeButton(L("history.delete"), symbol: "trash", action: #selector(deleteSelected))
        // Экспорт — действие по ВСЕЙ истории, поэтому отдельно (под списком слева), не в ряду с per-record.
        exportButton = makeButton(L("history.export"), symbol: "square.and.arrow.up", action: #selector(exportHistory))
        for b in [copyButton, playButton, deleteButton, exportButton] { content.addSubview(b!) }

        emptyLabel = NSTextField(labelWithString: L("history.empty"))
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 14)
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.widthAnchor.constraint(equalToConstant: 250),

            listScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            listScroll.bottomAnchor.constraint(equalTo: exportButton.topAnchor, constant: -10),
            listScroll.widthAnchor.constraint(equalToConstant: 250),

            exportButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            exportButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            searchInfo.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 14),
            searchInfo.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            searchInfo.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            // Верх обеих панелей на одном уровне — раньше правая начиналась выше левой.
            detailScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 12),
            detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            detailScroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),

            infoLabel.leadingAnchor.constraint(equalTo: detailScroll.leadingAnchor, constant: 2),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -8),
            infoLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            deleteButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            playButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            playButton.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: detailScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: detailScroll.centerYAnchor),
        ])
    }

    private func makeButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let b = NSButton(title: " " + title, target: self, action: action)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.bezelStyle = .rounded
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        b.imagePosition = .imageLeading
        return b
    }

    // MARK: - Экспорт истории

    @objc private func exportHistory() {
        guard !allRecords.isEmpty else { return }
        let recs = allRecords   // снимок на момент открытия диалога; фильтр поиска не влияет (§7)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = L("history.export")

        // Аксессуар: выбор формата (ручные фреймы — надёжнее автолейаута для accessoryView)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 46))
        let label = NSTextField(labelWithString: L("history.export.format"))
        label.frame = NSRect(x: 12, y: 13, width: 76, height: 20)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        let popup = NSPopUpButton(frame: NSRect(x: 94, y: 8, width: 250, height: 26))
        for f in HistoryExporter.Format.allCases {
            popup.addItem(withTitle: f.displayName)
            popup.lastItem?.representedObject = f.rawValue
        }
        popup.target = self
        popup.action = #selector(exportFormatChanged)
        accessory.addSubview(label)
        accessory.addSubview(popup)
        panel.accessoryView = accessory
        exportPanel = panel
        exportPopup = popup

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "voica-history-\(df.string(from: Date())).md"

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            defer { self?.exportPanel = nil; self?.exportPopup = nil }
            guard resp == .OK, let url = panel.url else { return }
            let raw = popup.selectedItem?.representedObject as? String ?? "markdown"
            let fmt = HistoryExporter.Format(rawValue: raw) ?? .markdown
            let content = HistoryExporter.serialize(recs, as: fmt)
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSSound.beep()
            }
        }
        if let window = window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    /// Смена формата в попапе — подменяем расширение в поле имени файла.
    @objc private func exportFormatChanged() {
        guard let panel = exportPanel, let popup = exportPopup,
              let raw = popup.selectedItem?.representedObject as? String,
              let f = HistoryExporter.Format(rawValue: raw) else { return }
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + f.ext
    }

    // MARK: - Данные

    /// Перезагрузить из БД и показать окно.
    func reloadAndShow() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Обновить список, если окно открыто (после новой диктовки).
    func refreshIfVisible() {
        guard window?.isVisible == true else { return }
        reload()
    }

    @objc private func searchChanged() { applyFilter(); updateDetailForSelection() }

    /// Cmd+F ставит курсор в поиск. Ожидаемый жест: без него поле приходится искать мышью.
    func focusSearch() { window?.makeFirstResponder(searchField) }

    /// Ищем по показанному тексту И по сырому (§7): человек помнит, что он сказал,
    /// а не то, во что это превратили правила и модель.
    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            records = allRecords
        } else {
            records = allRecords.filter {
                $0.text.localizedCaseInsensitiveContains(q)
                    || ($0.rawText?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        emptyLabel.stringValue = allRecords.isEmpty ? L("history.empty") : L("history.search.none")
        tableView.reloadData()
        if records.isEmpty {
            updateDetail(nil)
        } else {
            let row = min(max(tableView.selectedRow, 0), records.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            updateDetailForSelection()
        }
    }

    private func reload() {
        allRecords = Store.shared.all()
        // Экспорт остаётся действием по ВСЕЙ истории (§7), фильтр на него не влияет.
        exportButton.isEnabled = !allRecords.isEmpty
        applyFilter()
    }

    private var selectedRecord: TranscriptRecord? {
        let row = tableView.selectedRow
        return records.indices.contains(row) ? records[row] : nil
    }

    private var selectedRecords: [TranscriptRecord] {
        tableView.selectedRowIndexes.compactMap { records.indices.contains($0) ? records[$0] : nil }
    }

    /// Правая панель по текущему выделению. Текст, копирование и проигрывание осмысленны только
    /// для одной записи, поэтому при пачке показываем счётчик и оставляем активным лишь удаление.
    private func updateDetailForSelection() {
        let picked = selectedRecords
        guard picked.count > 1 else { updateDetail(picked.first); return }
        stopPlayback()
        emptyLabel.isHidden = true
        detailText.string = ""
        infoLabel.stringValue = L("history.selected", picked.count)
        copyButton.isEnabled = false
        playButton.isEnabled = false
        deleteButton.isEnabled = true
    }

    /// Показывает текст записи, подсвечивая совпадения с поиском. Для пятиминутной диктовки
    /// найти запись мало — надо ещё увидеть, ГДЕ внутри неё нужное место. Новых элементов
    /// интерфейса это не добавляет: подсветка и прокрутка к первому совпадению, больше ничего.
    @discardableResult
    private func setDetailText(_ text: String) -> Int {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { detailText.string = text; return 0 }

        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ])
        var first: NSRange?
        var count = 0
        var from = text.startIndex
        while let r = text.range(of: q, options: .caseInsensitive, range: from..<text.endIndex) {
            let ns = NSRange(r, in: text)
            attr.addAttributes([.backgroundColor: NSColor.systemYellow.withAlphaComponent(0.45)],
                               range: ns)
            if first == nil { first = ns }
            count += 1
            from = r.upperBound
        }
        detailText.textStorage?.setAttributedString(attr)
        if let f = first { detailText.scrollRangeToVisible(f) }
        return count
    }

    private func updateDetail(_ record: TranscriptRecord?) {
        stopPlayback()
        guard let r = record else {
            detailText.string = ""
            infoLabel.stringValue = ""
            searchInfo.stringValue = ""
            emptyLabel.isHidden = !records.isEmpty
            [copyButton, playButton, deleteButton].forEach { $0?.isEnabled = false }
            return
        }
        emptyLabel.isHidden = true
        let matches = setDetailText(r.text)

        var parts = [Self.dateFormatter.string(from: r.createdAt)]
        if let l = r.language { parts.append(l) }
        if let d = r.durationSec { parts.append(L("common.seconds", d)) }
        if let m = r.model, !m.isEmpty { parts.append(m) }   // движок/модель: whisper… / gigaam…
        infoLabel.stringValue = parts.joined(separator: " · ")

        // Сколько совпадений в ЭТОЙ записи — иначе на длинной диктовке видно только первое,
        // и непонятно, стоит ли листать дальше. Отдельный случай: запись попала в список
        // по сырому тексту (§7), а в показанном её нет — без пояснения это выглядит багом.
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { searchInfo.stringValue = "" }
        else if matches > 0 { searchInfo.stringValue = L("history.search.matches", matches) }
        else if r.rawText?.localizedCaseInsensitiveContains(q) == true {
            searchInfo.stringValue = L("history.search.inRaw")
        } else { searchInfo.stringValue = "" }

        copyButton.isEnabled = true
        deleteButton.isEnabled = true
        playButton.isEnabled = Store.shared.audioURL(for: r) != nil
        setPlayTitle(playing: false)
    }

    // MARK: - Действия

    @objc private func copyText() {
        guard let r = selectedRecord else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(r.text, forType: .string)
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        copyButton.title = " " + L("result.copied")
        resetCopyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
            self?.copyButton.title = " " + L("result.copy")
        }
        resetCopyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    @objc private func togglePlay() {
        if player?.isPlaying == true { stopPlayback(); return }
        guard let r = selectedRecord, let url = Store.shared.audioURL(for: r) else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            setPlayTitle(playing: true)
        } catch {
            NSLog("Voica: не удалось воспроизвести аудио: \(error.localizedDescription)")
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        setPlayTitle(playing: false)
    }

    private func setPlayTitle(playing: Bool) {
        playButton.image = NSImage(systemSymbolName: playing ? "stop.fill" : "play.fill",
                                   accessibilityDescription: playing ? "Stop" : "Play")
        playButton.title = playing ? " " + L("history.stop") : " " + L("history.play")
    }

    @objc private func deleteSelected() {
        let picked = selectedRecords
        guard !picked.isEmpty else { return }
        let alert = NSAlert()
        // Для пачки — счётчик в заголовке: сколько именно записей исчезнет.
        alert.messageText = picked.count == 1
            ? L("history.deleteConfirm.title")
            : L("history.deleteConfirm.titleMany", picked.count)
        alert.informativeText = L("history.deleteConfirm.msg")
        alert.addButton(withTitle: L("common.delete"))
        alert.addButton(withTitle: L("common.cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Store.shared.delete(ids: picked.map(\.id))
        reload()
    }
}

// MARK: - Таблица

extension HistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { records.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField)
            ?? {
                let tf = NSTextField(wrappingLabelWithString: "")
                tf.identifier = id
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.maximumNumberOfLines = 2
                tf.lineBreakMode = .byTruncatingTail
                return tf
            }()

        let r = records[row]
        let date = Self.dateFormatter.string(from: r.createdAt)
        let snippet = r.text.replacingOccurrences(of: "\n", with: " ")
        let attr = NSMutableAttributedString(
            string: date + "\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor])
        attr.append(NSAttributedString(
            string: snippet,
            attributes: [.font: NSFont.systemFont(ofSize: 13),
                         .foregroundColor: NSColor.labelColor]))
        cell.attributedStringValue = attr
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetailForSelection()
    }
}

/// Таблица, отдающая клавишу Delete/Backspace наружу: удалять выделенное с клавиатуры —
/// ожидаемое поведение маковского списка, особенно когда выделять можно пачкой.
/// Окно истории: перехватывает Cmd+F, где бы ни стоял фокус — в списке, в тексте записи
/// или нигде. Через `keyEquivalent` кнопки это не сделать: скрытые кнопки на них не отвечают.
final class HistoryWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            (windowController as? HistoryWindowController)?.focusSearch()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class HistoryTableView: NSTableView {
    var onDeleteKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let deleteKeys: Set<UInt16> = [51, 117]   // Backspace, Forward Delete
        if deleteKeys.contains(event.keyCode), selectedRow >= 0 {
            onDeleteKey?()
            return
        }
        super.keyDown(with: event)
    }
}

extension HistoryWindowController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        setPlayTitle(playing: false)
        self.player = nil
    }
}
