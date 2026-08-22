// Genera el icono de la app (PNG por tamaño) sin depender de recursos externos.
// Uso: swift tools/MakeIcon.swift <carpeta-destino>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)
    let squircle = NSBezierPath(roundedRect: body, xRadius: size * 0.22, yRadius: size * 0.22)

    ctx.saveGState()
    squircle.addClip()
    let gradient = NSGradient(colors: [NSColor(calibratedWhite: 0.16, alpha: 1),
                                       NSColor(calibratedWhite: 0.04, alpha: 1)])!
    gradient.draw(in: body, angle: -90)

    // La "isla" centrada
    let islandW = body.width * 0.56
    let islandH = body.height * 0.20
    let islandRect = CGRect(x: body.midX - islandW / 2,
                            y: body.midY - islandH / 2,
                            width: islandW, height: islandH)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: islandRect, xRadius: islandH / 2, yRadius: islandH / 2).fill()

    let glow = NSGradient(colors: [NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 0.95),
                                   NSColor(calibratedRed: 0.65, green: 0.45, blue: 1, alpha: 0.95)])!
    let dot = CGRect(x: islandRect.minX + islandH * 0.28,
                     y: islandRect.midY - islandH * 0.22,
                     width: islandH * 0.44, height: islandH * 0.44)
    glow.draw(in: NSBezierPath(ovalIn: dot), angle: -45)

    NSColor(calibratedWhite: 1, alpha: 0.85).setFill()
    let barW = islandH * 0.10
    for i in 0..<3 {
        let h = islandH * [0.28, 0.5, 0.36][i]
        let x = islandRect.maxX - islandH * (0.9 - Double(i) * 0.22)
        NSBezierPath(roundedRect: CGRect(x: x, y: islandRect.midY - h / 2, width: barW, height: h),
                     xRadius: barW / 2, yRadius: barW / 2).fill()
    }
    ctx.restoreGState()

    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    squircle.lineWidth = max(1, size * 0.006)
    squircle.stroke()
    image.unlockFocus()
    return image
}

for size in sizes {
    let img = drawIcon(size: CGFloat(size))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let scale = size <= 512 ? "" : ""
    _ = scale
    let base = size / 2
    let name: String
    if size == 1024 { name = "icon_512x512@2x.png" }
    else if size == 16 { name = "icon_16x16.png" }
    else { name = "icon_\(size)x\(size).png" }
    try? png.write(to: URL(fileURLWithPath: outDir + "/" + name))
    if size >= 32 {
        try? png.write(to: URL(fileURLWithPath: outDir + "/icon_\(base)x\(base)@2x.png"))
    }
}
print("iconos generados en \(outDir)")
