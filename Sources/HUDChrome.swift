// Общее оформление плавающих HUD-плашек (RecordingHUD и PrepHUD), чтобы они выглядели
// как одна вещь: капсула-блюр, светлый спиннер, светлая подпись.

import Cocoa

enum HUDChrome {
    /// Маска-капсула для NSVisualEffectView: девятичастная растяжимая картинка с capInsets,
    /// поэтому один и тот же образ подходит под любой размер плашки.
    ///
    /// Именно маска, а НЕ layer.cornerRadius: при blendingMode = .behindWindow размытие рисует
    /// оконный сервер за пределами слоя, masksToBounds его не обрезает и углы остаются острыми.
    static func capsuleMask(radius r: CGFloat) -> NSImage {
        let side = r * 2 + 1
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }

    /// Подложка плашки: тёмный системный блюр со скруглением под капсулу.
    static func blurBackdrop(size: NSSize, cornerRadius: CGFloat) -> NSVisualEffectView {
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.maskImage = capsuleMask(radius: cornerRadius)
        return blur
    }

    /// Спиннер поверх тёмного блюра — принудительно светлый, иначе на HUD он тонет.
    static func spinner(_ size: NSControl.ControlSize) -> NSProgressIndicator {
        let s = NSProgressIndicator()
        s.style = .spinning
        s.controlSize = size
        s.isIndeterminate = true
        s.appearance = NSAppearance(named: .vibrantDark)
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    /// Подпись поверх тёмного блюра: белая, независимо от системной темы.
    static func label(_ text: String, size: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: .medium)
        l.textColor = NSColor.white.withAlphaComponent(0.9)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }
}
