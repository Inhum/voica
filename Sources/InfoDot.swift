// Мини-иконка «ⓘ» с всплывающей подсказкой ПРИ НАВЕДЕНИИ (без системной задержки tooltip).
// Понятно, что на неё надо навести; поповер показывается сразу и закрывается при уходе мыши.
// Экономит высоту окна настроек (подсказка не занимает место в потоке).

import Cocoa

final class InfoDot: NSView {
    private let text: String
    private var popover: NSPopover?

    init(_ text: String) {
        self.text = text
        super.init(frame: NSRect(x: 0, y: 0, width: 15, height: 15))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 15).isActive = true
        heightAnchor.constraint(equalToConstant: 15).isActive = true

        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: text)
        iv.contentTintColor = .tertiaryLabelColor
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        iv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { showPopover() }
    override func mouseExited(with event: NSEvent)  { popover?.performClose(nil); popover = nil }

    private func showPopover() {
        guard popover == nil else { return }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            label.widthAnchor.constraint(equalToConstant: 260),
        ])

        let vc = NSViewController()
        vc.view = content
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = vc
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        popover = pop
    }
}
