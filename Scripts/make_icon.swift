// Renders a 1024×1024 app-icon master PNG (custom art, no SF Symbols).
// Usage: swift make_icon.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let S: CGFloat = 1024

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded "squircle" background with the app gradient.
let margin: CGFloat = 90
let rect = CGRect(x: margin, y: margin, width: S - margin * 2, height: S - margin * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
bg.addClip()

let top = NSColor(calibratedRed: 0.32, green: 0.56, blue: 0.98, alpha: 1).cgColor      // blue
let bottom = NSColor(calibratedRed: 0.60, green: 0.36, blue: 0.98, alpha: 1).cgColor   // violet
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY),
                       options: [])

// Custom lightning-bolt path (normalised, y-up), centred in the art area.
let boltPoints: [(CGFloat, CGFloat)] = [
    (0.575, 0.94), (0.315, 0.505), (0.475, 0.505),
    (0.425, 0.06), (0.715, 0.525), (0.545, 0.525)
]
let inset: CGFloat = 200
let box = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let bolt = NSBezierPath()
for (i, p) in boltPoints.enumerated() {
    let pt = NSPoint(x: box.minX + p.0 * box.width, y: box.minY + p.1 * box.height)
    if i == 0 { bolt.move(to: pt) } else { bolt.line(to: pt) }
}
bolt.close()

// Soft shadow, then white fill.
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 34,
              color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor.white.setFill()
bolt.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
