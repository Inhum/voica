// Окно «О Voica»: версия, ссылка на GitHub, лицензия.

import Cocoa

final class AboutWindowController: NSWindowController {
    static let repoURL = "https://github.com/Inhum/voica"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "О Voica"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("voica-main")
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
        ])

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Voica")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        stack.addArrangedSubview(icon)

        let name = NSTextField(labelWithString: "Voica")
        name.font = .boldSystemFont(ofSize: 20)
        stack.addArrangedSubview(name)

        let ver = NSTextField(labelWithString: "Версия \(appVersion)")
        ver.textColor = .secondaryLabelColor
        stack.addArrangedSubview(ver)

        let desc = NSTextField(labelWithString: "Диктовка с пунктуацией через Groq Whisper")
        desc.textColor = .secondaryLabelColor
        desc.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(desc)

        let gh = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        gh.bezelStyle = .rounded
        stack.addArrangedSubview(gh)

        let lic = NSTextField(labelWithString: "© 2026 Ivan Ushakov · MIT License")
        lic.textColor = .tertiaryLabelColor
        lic.font = .systemFont(ofSize: 10)
        stack.addArrangedSubview(lic)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openGitHub() {
        if let url = URL(string: Self.repoURL) { NSWorkspace.shared.open(url) }
    }
}
