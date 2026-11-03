#!/usr/bin/env swift
// Renders the Lock In app icon at every macOS size and writes Contents.json.
//
// Usage: swift Scripts/generate_icon.swift <outdir>
//   e.g. swift Scripts/generate_icon.swift LockIn/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit
import CoreGraphics
import Foundation

// MARK: - Sizes

struct Variant {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png" }
}

let variants: [Variant] = [
    Variant(points: 16, scale: 1), Variant(points: 16, scale: 2),
    Variant(points: 32, scale: 1), Variant(points: 32, scale: 2),
    Variant(points: 128, scale: 1), Variant(points: 128, scale: 2),
    Variant(points: 256, scale: 1), Variant(points: 256, scale: 2),
    Variant(points: 512, scale: 1), Variant(points: 512, scale: 2),
]

// MARK: - Drawing (authored on a 1024 x 1024 canvas)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

/// Superellipse ("squircle") path, closer to the macOS icon shape than a rounded rect.
func squirclePath(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    ctx.clear(canvas)

    // Icon body: 824 x 824 centered (macOS icon grid), leaving room for the drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squirclePath(in: body)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0.10, 0.08, 0.30, 0.38))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0.35, 0.30, 0.90))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient: indigo -> violet
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgb(0.30, 0.36, 0.95), rgb(0.60, 0.33, 0.96)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Soft glow in the upper left
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgb(1, 1, 1, 0.28), rgb(1, 1, 1, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: body.minX + 220, y: body.maxY - 150), startRadius: 0,
                           endCenter: CGPoint(x: body.minX + 220, y: body.maxY - 150), endRadius: 520,
                           options: [])

    // Faint focus rings behind the glyph
    ctx.setStrokeColor(rgb(1, 1, 1, 0.07))
    ctx.setLineWidth(10)
    for r in [250.0, 330.0, 410.0] as [CGFloat] {
        ctx.strokeEllipse(in: CGRect(x: body.midX - r, y: body.midY - r - 10, width: r * 2, height: r * 2))
    }
    ctx.restoreGState()

    // Inner edge highlight
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.22))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // Glyph: a padlock whose keyhole is a focus target.
    let cx = body.midX
    let bodyW: CGFloat = 340, bodyH: CGFloat = 270
    let lockBody = CGRect(x: cx - bodyW / 2, y: 330, width: bodyW, height: bodyH)

    // Shackle
    let shackleW: CGFloat = 214
    let shackleThickness: CGFloat = 50
    let shackleTop: CGFloat = lockBody.maxY + 170
    let shackle = CGMutablePath()
    let left = cx - shackleW / 2 + shackleThickness / 2
    let right = cx + shackleW / 2 - shackleThickness / 2
    shackle.move(to: CGPoint(x: left, y: lockBody.maxY - 10))
    shackle.addLine(to: CGPoint(x: left, y: shackleTop - (right - left) / 2))
    shackle.addArc(center: CGPoint(x: cx, y: shackleTop - (right - left) / 2),
                   radius: (right - left) / 2, startAngle: .pi, endAngle: 0, clockwise: true)
    shackle.addLine(to: CGPoint(x: right, y: lockBody.maxY - 10))

    func drawGlyph(_ ctx: CGContext, color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(shackleThickness)
        ctx.setLineCap(.round)
        ctx.addPath(shackle)
        ctx.strokePath()
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: lockBody, cornerWidth: 70, cornerHeight: 70, transform: nil))
        ctx.fillPath()
    }

    // Glyph shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: rgb(0.12, 0.08, 0.40, 0.35))
    drawGlyph(ctx, color: rgb(1, 1, 1))
    ctx.restoreGState()

    // Subtle vertical shading on the lock body
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: lockBody, cornerWidth: 70, cornerHeight: 70, transform: nil))
    ctx.clip()
    let shade = CGGradient(colorsSpace: space,
                           colors: [rgb(1, 1, 1, 0), rgb(0.55, 0.50, 0.95, 0.22)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: lockBody.maxY), end: CGPoint(x: 0, y: lockBody.minY), options: [])
    ctx.restoreGState()

    // Keyhole as a focus target: ring + dot, in the background gradient colour.
    let center = CGPoint(x: cx, y: lockBody.midY)
    let keyColor = rgb(0.42, 0.34, 0.95)
    ctx.setStrokeColor(keyColor)
    ctx.setLineWidth(22)
    ctx.strokeEllipse(in: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124))
    ctx.setFillColor(keyColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48))
}

// MARK: - Rendering

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift generate_icon.swift <outdir>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for v in variants {
    guard let data = render(pixels: v.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(v.filename)\n".utf8))
        exit(1)
    }
    try data.write(to: outDir.appendingPathComponent(v.filename))
    images.append([
        "filename": v.filename,
        "idiom": "mac",
        "scale": "\(v.scale)x",
        "size": "\(v.points)x\(v.points)",
    ])
    print("wrote \(v.filename) (\(v.pixels)px)")
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote Contents.json")
