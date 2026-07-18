// Плавающий индикатор «Готовлю модель распознавания…» в стиле системного HUD.
// Показывается, когда локальная диктовка ждёт ПЕРВУЮ загрузку модели (десятки секунд:
// разовая подгонка CoreML-модели под Neural Engine). Без него это выглядит как зависание.
// Не перехватывает фокус и клики; сам исчезает по hide().

import Cocoa

final class PrepHUD {
    private var panel: NSPanel?

    /// Показать HUD с текстом. Идемпотентно (повторный show не плодит панели). Главный поток.
    func show(_ text: String) {
        guard panel == nil else { return }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 72),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2,
                                         y: f.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Скрыть HUD. Главный поток.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
