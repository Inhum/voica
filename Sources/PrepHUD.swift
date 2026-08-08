// Плавающий индикатор «Готовлю модель распознавания…».
// Показывается, когда локальная диктовка ждёт ПЕРВУЮ загрузку модели (десятки секунд:
// разовая подгонка CoreML-модели под Neural Engine). Без него это выглядит как зависание.
// Не перехватывает фокус и клики; сам исчезает по hide().
// Оформление — общее с плашкой записи (RecordingHUD) через HUDChrome: та же капсула-блюр со
// скруглением через maskImage, тот же светлый спиннер с подписью. Отличается только позицией
// (центр экрана — событие редкое и важное) и размером.

import Cocoa

final class PrepHUD {
    private var panel: NSPanel?

    /// Показать HUD с текстом. Идемпотентно (повторный show не плодит панели). Главный поток.
    func show(_ text: String) {
        guard panel == nil else { return }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 56),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = HUDChrome.blurBackdrop(size: panel.frame.size, cornerRadius: 28)
        blur.autoresizingMask = [.width, .height]
        panel.contentView = blur

        let spinner = HUDChrome.spinner(.small)
        spinner.startAnimation(nil)
        let label = HUDChrome.label(text, size: 13)

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 10
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
