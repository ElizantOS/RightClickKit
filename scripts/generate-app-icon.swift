#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let assetsURL = repoRoot.appendingPathComponent("assets", isDirectory: true)
let iconsetURL = assetsURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let pngURL = assetsURL.appendingPathComponent("AppIcon-1024.png")
let icnsURL = assetsURL.appendingPathComponent("AppIcon.icns")

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawShadow(offset: CGSize, blur: CGFloat, alpha: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowOffset = offset
    shadow.shadowBlurRadius = blur
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.set()
}

func drawFolder(in rect: CGRect) {
    NSGraphicsContext.saveGraphicsState()
    drawShadow(offset: CGSize(width: 0, height: -18), blur: 34, alpha: 0.26)

    let tab = NSBezierPath(roundedRect: CGRect(
        x: rect.minX + 34,
        y: rect.maxY - 118,
        width: rect.width * 0.42,
        height: 112
    ), xRadius: 38, yRadius: 38)
    color(247, 192, 74).setFill()
    tab.fill()

    let body = roundedRect(rect, radius: 64)
    NSGradient(
        starting: color(255, 203, 91),
        ending: color(233, 145, 54)
    )?.draw(in: body, angle: -90)

    color(255, 239, 176, 0.42).setFill()
    roundedRect(CGRect(x: rect.minX + 42, y: rect.maxY - 102, width: rect.width - 84, height: 44), radius: 22).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawMenu(in rect: CGRect) {
    NSGraphicsContext.saveGraphicsState()
    drawShadow(offset: CGSize(width: 0, height: -24), blur: 42, alpha: 0.30)

    let panel = roundedRect(rect, radius: 56)
    NSGradient(
        starting: color(255, 255, 250),
        ending: color(231, 242, 238)
    )?.draw(in: panel, angle: -90)

    color(16, 48, 56, 0.12).setStroke()
    panel.lineWidth = 4
    panel.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let rows = [
        CGRect(x: rect.minX + 54, y: rect.maxY - 134, width: rect.width - 108, height: 74),
        CGRect(x: rect.minX + 54, y: rect.maxY - 242, width: rect.width - 108, height: 74),
        CGRect(x: rect.minX + 54, y: rect.maxY - 350, width: rect.width - 108, height: 74)
    ]

    for (index, row) in rows.enumerated() {
        color(32, 72, 78, index == 1 ? 0.12 : 0.08).setFill()
        roundedRect(row, radius: 24).fill()
        color(37, 71, 80, 0.22).setFill()
        roundedRect(CGRect(x: row.minX + 92, y: row.midY - 8, width: row.width - 124, height: 16), radius: 8).fill()
    }

    drawTreeGlyph(in: rows[0])
    drawPieGlyph(in: rows[1])
    drawTerminalGlyph(in: rows[2])
}

func drawTreeGlyph(in row: CGRect) {
    let x = row.minX + 35
    let y = row.midY
    color(20, 145, 126).setStroke()
    let path = NSBezierPath()
    path.lineWidth = 8
    path.lineCapStyle = .round
    path.move(to: CGPoint(x: x + 10, y: y + 22))
    path.line(to: CGPoint(x: x + 10, y: y - 22))
    path.move(to: CGPoint(x: x + 10, y: y + 10))
    path.line(to: CGPoint(x: x + 42, y: y + 10))
    path.move(to: CGPoint(x: x + 10, y: y - 14))
    path.line(to: CGPoint(x: x + 42, y: y - 14))
    path.stroke()

    for point in [
        CGPoint(x: x + 10, y: y + 22),
        CGPoint(x: x + 48, y: y + 10),
        CGPoint(x: x + 48, y: y - 14)
    ] {
        color(20, 145, 126).setFill()
        NSBezierPath(ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)).fill()
    }
}

func drawPieGlyph(in row: CGRect) {
    let rect = CGRect(x: row.minX + 24, y: row.midY - 26, width: 52, height: 52)
    color(239, 109, 72).setFill()
    NSBezierPath(ovalIn: rect).fill()

    let wedge = NSBezierPath()
    wedge.move(to: CGPoint(x: rect.midX, y: rect.midY))
    wedge.appendArc(withCenter: CGPoint(x: rect.midX, y: rect.midY), radius: 26, startAngle: 18, endAngle: 110)
    wedge.close()
    color(58, 170, 154).setFill()
    wedge.fill()

    color(255, 255, 255, 0.95).setStroke()
    wedge.lineWidth = 5
    wedge.stroke()
}

func drawTerminalGlyph(in row: CGRect) {
    color(42, 80, 88).setStroke()
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = 8
    let x = row.minX + 28
    let y = row.midY
    path.move(to: CGPoint(x: x, y: y + 18))
    path.line(to: CGPoint(x: x + 22, y: y))
    path.line(to: CGPoint(x: x, y: y - 18))
    path.move(to: CGPoint(x: x + 34, y: y - 20))
    path.line(to: CGPoint(x: x + 62, y: y - 20))
    path.stroke()
}

func drawCursor() {
    let cursor = NSBezierPath()
    cursor.move(to: CGPoint(x: 248, y: 704))
    cursor.line(to: CGPoint(x: 248, y: 254))
    cursor.line(to: CGPoint(x: 366, y: 362))
    cursor.line(to: CGPoint(x: 428, y: 206))
    cursor.line(to: CGPoint(x: 512, y: 240))
    cursor.line(to: CGPoint(x: 448, y: 398))
    cursor.line(to: CGPoint(x: 610, y: 398))
    cursor.close()

    NSGraphicsContext.saveGraphicsState()
    drawShadow(offset: CGSize(width: 0, height: -18), blur: 24, alpha: 0.32)
    color(249, 253, 249).setFill()
    cursor.fill()
    NSGraphicsContext.restoreGraphicsState()

    color(13, 42, 49).setStroke()
    cursor.lineWidth = 22
    cursor.lineJoinStyle = .round
    cursor.stroke()

    color(255, 255, 255, 0.52).setFill()
    NSBezierPath(ovalIn: CGRect(x: 532, y: 612, width: 54, height: 54)).fill()
    color(255, 255, 255, 0.30).setFill()
    NSBezierPath(ovalIn: CGRect(x: 596, y: 574, width: 32, height: 32)).fill()
}

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

let baseRect = CGRect(x: 72, y: 72, width: 880, height: 880)
let base = roundedRect(baseRect, radius: 204)
NSGradient(
    starting: color(12, 93, 104),
    ending: color(14, 33, 42)
)?.draw(in: base, angle: 55)

color(255, 255, 255, 0.16).setStroke()
base.lineWidth = 10
base.stroke()

color(255, 255, 255, 0.08).setFill()
NSBezierPath(ovalIn: CGRect(x: 628, y: 676, width: 196, height: 196)).fill()
color(255, 255, 255, 0.06).setFill()
NSBezierPath(ovalIn: CGRect(x: 142, y: 162, width: 260, height: 260)).fill()

drawFolder(in: CGRect(x: 150, y: 214, width: 558, height: 386))
drawMenu(in: CGRect(x: 430, y: 324, width: 424, height: 470))
drawCursor()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Could not render icon PNG.")
}

try pngData.write(to: pngURL)

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconFiles {
    let destination = iconsetURL.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(size)", "\(size)", pngURL.path, "--out", destination.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("sips failed for \(name)")
    }
}

if fileManager.fileExists(atPath: icnsURL.path) {
    try fileManager.removeItem(at: icnsURL)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}

print("Wrote \(pngURL.path)")
print("Wrote \(icnsURL.path)")
