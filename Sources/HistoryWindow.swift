// Окно История: список транскрибаций слева, подробности справа.
// Действия: копировать текст, проиграть аудио (если хранится), удалить запись.

import Cocoa
import AVFoundation

final class HistoryWindowController: NSWindowController {
    private var records: [TranscriptRecord] = []
    private var tableView: NSTableView!
    private var detailText: NSTextView!
    private var infoLabel: NSTextField!
    private var copyButton: NSButton!
    private var playButton: NSButton!
    private var deleteButton: NSButton!
    private var emptyLabel: NSTextField!
    private var player: AVAudioPlayer?
    private var resetCopyWork: DispatchWorkItem?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
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

        // Список слева
        let listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 50
        table.usesAutomaticRowHeights = false
        let col = NSTableColumn(identifier: .init("entry"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.target = self
        listScroll.documentView = table
        tableView = table
        content.addSubview(listScroll)

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
        for b in [copyButton, playButton, deleteButton] { content.addSubview(b!) }

        emptyLabel = NSTextField(labelWithString: L("history.empty"))
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 14)
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            listScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            listScroll.widthAnchor.constraint(equalToConstant: 250),

            detailScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
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

    private func reload() {
        records = Store.shared.all()
        tableView.reloadData()
        if records.isEmpty {
            updateDetail(nil)
        } else {
            let row = min(max(tableView.selectedRow, 0), records.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            updateDetail(records[row])
        }
    }

    private var selectedRecord: TranscriptRecord? {
        let row = tableView.selectedRow
        return records.indices.contains(row) ? records[row] : nil
    }

    private func updateDetail(_ record: TranscriptRecord?) {
        stopPlayback()
        guard let r = record else {
            detailText.string = ""
            infoLabel.stringValue = ""
            emptyLabel.isHidden = !records.isEmpty
            [copyButton, playButton, deleteButton].forEach { $0?.isEnabled = false }
            return
        }
        emptyLabel.isHidden = true
        detailText.string = r.text

        var parts = [Self.dateFormatter.string(from: r.createdAt)]
        if let l = r.language { parts.append(l) }
        if let d = r.durationSec { parts.append(L("common.seconds", d)) }
        if let m = r.model, !m.isEmpty { parts.append(m) }   // движок/модель: whisper… / gigaam…
        infoLabel.stringValue = parts.joined(separator: " · ")

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
        guard let r = selectedRecord else { return }
        let alert = NSAlert()
        alert.messageText = L("history.deleteConfirm.title")
        alert.informativeText = L("history.deleteConfirm.msg")
        alert.addButton(withTitle: L("common.delete"))
        alert.addButton(withTitle: L("common.cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Store.shared.delete(id: r.id)
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
        updateDetail(selectedRecord)
    }
}

extension HistoryWindowController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        setPlayTitle(playing: false)
        self.player = nil
    }
}
