#!/usr/bin/env swift
import AppKit

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let gradient = NSGradient(colors: [color(0x8A1020), color(0xA6192E), color(0x6E0A18)])
gradient?.draw(in: rect, angle: -55)

// Subtle concentric arcs.
for index in 0..<6 {
    let inset = CGFloat(index) * 64
    let path = NSBezierPath(ovalIn: NSRect(x: 512 - 640 + inset, y: 512 - 640 + inset,
                                           width: 1280 - inset * 2, height: 1280 - inset * 2))
    NSColor.white.withAlphaComponent(0.05).setStroke()
    path.lineWidth = 2
    path.stroke()
}

// Graduation cap glyph.
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let symbolSize = symbol.size
    let target = NSRect(x: (CGFloat(size) - symbolSize.width) / 2,
                        y: (CGFloat(size) - symbolSize.height) / 2 + 8,
                        width: symbolSize.width,
                        height: symbolSize.height)
    symbol.draw(in: target)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode icon")
}
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
