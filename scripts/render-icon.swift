#!/usr/bin/env swift
import AppKit
import Foundation

// Original vector artwork. Rebuilds the PNG and ICNS without downloaded assets.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let files = FileManager.default
let scratch = root.appendingPathComponent(".build/icon-render-\(UUID().uuidString).iconset")
try files.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? files.removeItem(at: scratch) }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func render(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "CodexNotchIcon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    graphics.cgContext.setAllowsAntialiasing(true)
    graphics.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860),
                            xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0.08, 0.09, 0.11).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.17, 0.19, 0.23), ending: color(0.065, 0.075, 0.095))!
        .draw(in: tile, angle: -90)
    color(1, 1, 1, 0.14).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    // A quiet screen surface gives the camera cutout its physical context.
    let screen = NSBezierPath(roundedRect: NSRect(x: 176, y: 270, width: 672, height: 506),
                              xRadius: 44, yRadius: 44)
    NSGradient(starting: color(0.29, 0.34, 0.42), ending: color(0.15, 0.18, 0.24))!
        .draw(in: screen, angle: -90)
    color(0.71, 0.80, 0.94, 0.18).setStroke()
    screen.lineWidth = 2
    screen.stroke()

    // Flat top and continuous lower corners, as on a MacBook camera housing.
    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: 324, y: 777))
    notch.line(to: NSPoint(x: 700, y: 777))
    notch.line(to: NSPoint(x: 700, y: 600))
    notch.curve(to: NSPoint(x: 658, y: 558), controlPoint1: NSPoint(x: 700, y: 572),
                controlPoint2: NSPoint(x: 686, y: 558))
    notch.line(to: NSPoint(x: 366, y: 558))
    notch.curve(to: NSPoint(x: 324, y: 600), controlPoint1: NSPoint(x: 338, y: 558),
                controlPoint2: NSPoint(x: 324, y: 572))
    notch.close()
    color(0.015, 0.02, 0.027).setFill()
    notch.fill()

    color(0.12, 0.145, 0.19).setFill()
    NSBezierPath(ovalIn: NSRect(x: 501, y: 674, width: 22, height: 22)).fill()
    color(0.30, 0.39, 0.52, 0.5).setFill()
    NSBezierPath(ovalIn: NSRect(x: 507, y: 686, width: 5, height: 5)).fill()

    // The status light is the only saturated accent; no text or third-party logo.
    let rim = NSBezierPath(roundedRect: NSRect(x: 369, y: 550, width: 286, height: 8),
                           xRadius: 4, yRadius: 4)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0.22, 0.59, 1, 0.45)
    glow.shadowBlurRadius = 18
    glow.shadowOffset = .zero
    glow.set()
    color(0.40, 0.73, 1).setFill()
    rim.fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexNotchIcon", code: 2)
    }
    return png
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(points)x\(points)\(suffix).png"
        try render(pixels: points * scale).write(to: scratch.appendingPathComponent(name))
    }
}

let assets = root.appendingPathComponent("docs/assets")
let resources = root.appendingPathComponent("Resources")
try files.createDirectory(at: assets, withIntermediateDirectories: true)
try files.createDirectory(at: resources, withIntermediateDirectories: true)
try render(pixels: 256).write(to: assets.appendingPathComponent("icon.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", resources.appendingPathComponent("AppIcon.icns").path,
                     scratch.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    try? files.removeItem(at: scratch)
    exit(process.terminationStatus)
}
print("Rendered docs/assets/icon.png (256 × 256) and Resources/AppIcon.icns")
