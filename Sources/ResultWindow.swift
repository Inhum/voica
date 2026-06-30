// Окно результата: показывает распознанный текст (редактируемый) и кнопку Copy.
// Текст автоматически копируется в буфер при показе.

import Cocoa

final class ResultWindowController: NSWindowController {
    private var textView: NSTextView!
    private var copyButton: NSButton!
    private var infoLabel: NSTextField!
    private var resetCopyIconWork: DispatchWorkItem?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Voica"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("voica-main")
        window.minSize = NSSize(width: 360, height: 200)
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Текст
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let tv = NSTextView()
        tv.isEditable = true
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        textView = tv
        content.addSubview(scroll)

        // Нижняя панель
        infoLabel = NSTextField(labelWithString: "")
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.font = .systemFont(ofSize: 11)
        content.addSubview(infoLabel)

        copyButton = NSButton(title: " " + L("result.copy"), target: self, action: #selector(copyText))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .rounded
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyButton.imagePosition = .imageLeading
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command, .shift]
        content.addSubview(copyButton)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),

            infoLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            infoLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    /// Показать текст: кладёт в буфер, обновляет окно (одно на все результаты)
    /// и выводит его на передний план.
    func show(_ transcription: Transcription) {
        let wasVisible = window?.isVisible ?? false

        // Снять фокус: если поле сейчас редактируется, присваивание .string
        // может не отрисоваться — поэтому сперва уводим первого респондера.
        window?.makeFirstResponder(nil)
        textView.string = transcription.text
        textView.scrollToBeginningOfDocument(nil)
        copyToPasteboard(transcription.text)

        var parts: [String] = [L("result.copiedToClipboard")]
        if let lang = transcription.language { parts.append(L("result.language", lang)) }
        if let d = transcription.duration { parts.append(L("common.seconds", d)) }
        infoLabel.stringValue = parts.joined(separator: " · ")

        if !wasVisible { window?.center() }   // не дёргать позицию уже открытого окна
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func copyText() {
        copyToPasteboard(textView.string)
        flashCopied()
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func flashCopied() {
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        copyButton.title = " " + L("result.copied")
        resetCopyIconWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
            self?.copyButton.title = " " + L("result.copy")
        }
        resetCopyIconWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
