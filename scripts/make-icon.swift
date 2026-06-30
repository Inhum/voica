// Генерирует .iconset для Voica: сквиркл с градиентом + звуковая волна.
// Запуск: swift scripts/make-icon.swift <output.iconset>
// Цвета иконки легко поменять ниже (topColor / bottomColor).

import AppKit

let topColor    = NSColor(srgbRed: 0.36, green: 0.66, blue: 1.00, alpha: 1) // светлее (верх)
let bottomColor = NSColor(srgbRed: 0.12, green: 0.44, blue: 0.90, alpha: 1) // темнее (низ)

func drawIcon(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Сквиркл (скруглённый квадрат) с полем по краям, как у иконок macOS.
    let margin = size * 0.09
    let rect = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let corner = rect.width * 0.2237
    let plate = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    NSGradient(starting: topColor, ending: bottomColor)!.draw(in: plate, angle: -90)

    // Звуковая волна: 7 симметричных столбиков со скруглёнными концами.
    let fracs: [CGFloat] = [0.35, 0.6, 0.85, 1.0, 0.85, 0.6, 0.35]
    let barW = rect.width * 0.06
    let gap  = barW * 0.7
    let maxH = rect.height * 0.6
    let total = CGFloat(fracs.count) * barW + CGFloat(fracs.count - 1) * gap
    var x = rect.midX - total / 2
    NSColor.white.setFill()
    for f in fracs {
        let h = maxH * f
        let bar = NSRect(x: x, y: rect.midY - h / 2, width: barW, height: h)
        NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16),   ("icon_16x16@2x", 32),
    ("icon_32x32", 32),   ("icon_32x32@2x", 64),
    ("icon_128x128", 128),("icon_128x128@2x", 256),
    ("icon_256x256", 256),("icon_256x256@2x", 512),
    ("icon_512x512", 512),("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try! drawIcon(px: px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote \(sizes.count) PNGs to \(out)")
