// Плавающий индикатор диктовки — плашка снизу по центру экрана (в духе Whisper / Siri).
// Живёт от старта записи до готового текста и проходит два состояния: «пишу» (анимированная
// волна + кнопки «×» отменить и «✓» остановить) и «распознаю» (спиннер с подписью, без кнопок).
// Пока плашка на экране, иконка в менюбаре не меняется — индикатор один, чтобы не рябило.
// Не перехватывает фокус. Стиль системного HUD.

import Cocoa

final class RecordingHUD: NSObject {
    private enum Mode { case recording, transcribing }

    private var panel: NSPanel?
    private var blur: NSVisualEffectView?
    private var stack: NSStackView?
    private var wave: WaveformView?
    private var mode: Mode?
    private var onCancel: (() -> Void)?
    private var onStop: (() -> Void)?

    private let w: CGFloat = 176, h: CGFloat = 44

    /// Показать плашку в состоянии «пишу». Идемпотентно. Главный поток.
    func show(onCancel: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onStop = onStop
        ensurePanel()
        guard mode != .recording else { return }
        mode = .recording

        let cancel = makeButton("xmark", action: #selector(cancelTapped),
                                symbolColor: NSColor.white.withAlphaComponent(0.85),
                                bg: NSColor.white.withAlphaComponent(0.14))
        let waveView = WaveformView(frame: NSRect(x: 0, y: 0, width: 72, height: 22))
        waveView.translatesAutoresizingMaskIntoConstraints = false
        waveView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        waveView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let stop = makeButton("checkmark", action: #selector(stopTapped),
                              symbolColor: .white, bg: NSColor.systemGreen)

        setContent([cancel, waveView, stop])
        waveView.start()
        wave = waveView
    }

    /// Перевести плашку в состояние «распознаю»: волна и кнопки уходят, остаётся спиннер с
    /// подписью. Вызывается только когда плашка уже на экране — своей плашки для распознавания
    /// без записи не бывает.
    func showTranscribing() {
        guard panel != nil, mode != .transcribing else { return }
        mode = .transcribing
        wave?.stop()
        wave = nil

        let spinner = HUDChrome.spinner(.small)
        let label = HUDChrome.label(L("hud.recognizing"), size: 12)

        setContent([spinner, label])
        spinner.startAnimation(nil)
    }

    /// Создаёт панель, если её ещё нет. Позиция и размер — фиксированные для обоих состояний,
    /// чтобы переход «пишу» → «распознаю» не дёргал плашку.
    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = HUDChrome.blurBackdrop(size: NSSize(width: w, height: h), cornerRadius: h / 2)
        panel.contentView = blur

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - w / 2, y: f.minY + 28))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        self.blur = blur
        self.stack = stack
    }

    /// Заменяет начинку плашки, оставляя саму панель на месте.
    private func setContent(_ views: [NSView]) {
        guard let stack else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        views.forEach { stack.addArrangedSubview($0) }
    }

    func hide() {
        wave?.stop()
        panel?.orderOut(nil)
        panel = nil
        blur = nil
        stack = nil
        wave = nil
        mode = nil
    }

    // MARK: - Кнопки

    private func makeButton(_ symbol: String, action: Selector,
                            symbolColor: NSColor, bg: NSColor) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                            ?? NSImage(), target: self, action: action)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleProportionallyDown
        b.contentTintColor = symbolColor
        b.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        b.wantsLayer = true
        b.layer?.cornerRadius = 14
        b.layer?.backgroundColor = bg.cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    // Плашку сами не прячем: она следует за состоянием диктовки. Отмена уводит в .idle (там
    // hide), стоп — в .transcribing (там смена начинки). Спрятать здесь значило бы убить панель
    // до того, как ей покажут «распознаю».
    @objc private func cancelTapped() { onCancel?() }
    @objc private func stopTapped()   { onStop?() }
}

/// Анимированная «волна» из вертикальных столбиков (симметрично от центра), таймер ~14 Гц.
final class WaveformView: NSView {
    private var bars: [CALayer] = []
    private var timer: Timer?
    private var phase = 0.0
    private let n = 7
    private let barW: CGFloat = 3
    private let gap: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for _ in 0..<n {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = barW / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        let totalW = CGFloat(n) * barW + CGFloat(n - 1) * gap
        let x0 = (bounds.width - totalW) / 2
        for (i, bar) in bars.enumerated() {
            bar.frame = NSRect(x: x0 + CGFloat(i) * (barW + gap),
                               y: bounds.midY - 2, width: barW, height: 4)
        }
    }

    func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 14.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        phase += 0.32
        let maxH = bounds.height - 4
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            let s = (sin(phase + Double(i) * 0.9) + 1) / 2           // 0…1
            let h = 4 + CGFloat(s) * (maxH - 4)
            bar.frame = NSRect(x: bar.frame.minX, y: (bounds.height - h) / 2, width: barW, height: h)
        }
        CATransaction.commit()
    }
}
