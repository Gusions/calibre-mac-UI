import AppKit

// Icona "Calibre Mac": minimale e sobria. Fondo avorio, tre dorsi in tinta unita, una mensola.
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func C(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let sq = CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Ombra di sistema, leggera
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: C(0x000000, 0.28))
ctx.addPath(sq); ctx.setFillColor(C(0xF4F1EA)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(sq); ctx.clip()
ctx.setFillColor(C(0xF4F1EA)); ctx.fill(rect)

let base: CGFloat = 292
func spine(x: CGFloat, w: CGFloat, h: CGFloat, color: UInt32, line: UInt32) {
    let p = CGPath(roundedRect: CGRect(x: x, y: base, width: w, height: h), cornerWidth: 10, cornerHeight: 10, transform: nil)
    ctx.addPath(p); ctx.setFillColor(C(color)); ctx.fillPath()
    // filetto sottile vicino alla testa e al piede
    ctx.setFillColor(C(line, 0.55))
    ctx.fill(CGRect(x: x + 18, y: base + h - 56, width: w - 36, height: 6))
    ctx.fill(CGRect(x: x + 18, y: base + 50, width: w - 36, height: 6))
}

spine(x: 292, w: 128, h: 404, color: 0x2B3036, line: 0xF4F1EA)
spine(x: 456, w: 128, h: 500, color: 0x9A3B34, line: 0xF4F1EA)
spine(x: 620, w: 128, h: 448, color: 0x7A8189, line: 0xF4F1EA)

// Mensola
ctx.setFillColor(C(0x2B3036))
ctx.addPath(CGPath(roundedRect: CGRect(x: 236, y: base - 22, width: 552, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil))
ctx.fillPath()

ctx.restoreGState()

// Filo del bordo
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.setStrokeColor(C(0x000000, 0.10)); ctx.setLineWidth(1.5); ctx.strokePath()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
