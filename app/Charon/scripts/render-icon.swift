// Renders the app icon into an .appiconset: swift scripts/render-icon.swift Charon/Assets.xcassets/AppIcon.appiconset
// Charon the ferryman: a hooded figure poling a narrow boat, silhouetted against a low moon, lantern at the bow.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> CGImage {
    let size = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: 824/1024 body with ~185 corner radius.
    let inset = size * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    // Unit coordinates inside the body, origin bottom-left.
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * body.width, y: body.minY + y * body.height) }
    func len(_ v: CGFloat) -> CGFloat { v * body.width }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.025, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x0B0E14)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()

    // Night sky.
    let sky = CGGradient(colorsSpace: nil, colors: [color(0x222B3C), color(0x0E121B)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: pt(0, 1), end: pt(0, 0.4), options: [.drawsAfterEndLocation])

    // Low moon behind the ferryman.
    let moonCenter = pt(0.58, 0.60)
    let moonRadius = len(0.27)
    let halo = CGGradient(colorsSpace: nil, colors: [color(0xE3A574, 0.35), color(0xE3A574, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: moonCenter, startRadius: moonRadius, endCenter: moonCenter,
                           endRadius: moonRadius * 1.6, options: [])
    let moon = CGGradient(colorsSpace: nil, colors: [color(0xF3C995), color(0xD48A4E)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2))
    ctx.clip()
    ctx.drawLinearGradient(moon, start: CGPoint(x: moonCenter.x, y: moonCenter.y + moonRadius),
                           end: CGPoint(x: moonCenter.x, y: moonCenter.y - moonRadius), options: [])
    ctx.restoreGState()

    // Water.
    let horizon: CGFloat = 0.40
    let water = CGGradient(colorsSpace: nil, colors: [color(0x141C29), color(0x080B11)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: body.minX, y: body.minY, width: body.width, height: len(horizon)))
    ctx.drawLinearGradient(water, start: pt(0, horizon), end: pt(0, 0), options: [])
    ctx.restoreGState()

    // Moonlight on the water.
    ctx.setLineCap(.round)
    for (y, half, alpha) in [(0.34, 0.16, 0.55), (0.28, 0.12, 0.4), (0.22, 0.08, 0.3), (0.16, 0.05, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.setStrokeColor(color(0xE3A574, alpha))
        ctx.setLineWidth(max(len(0.014), 1))
        ctx.move(to: pt(0.58 - half, y)); ctx.addLine(to: pt(0.58 + half, y)); ctx.strokePath()
    }

    let silhouette = color(0x05070B)
    ctx.setFillColor(silhouette)

    // Boat: long, low hull with raised ends.
    let hull = CGMutablePath()
    hull.move(to: pt(0.10, 0.50))
    hull.addQuadCurve(to: pt(0.90, 0.49), control: pt(0.50, 0.40))
    hull.addQuadCurve(to: pt(0.74, 0.37), control: pt(0.86, 0.39))
    hull.addLine(to: pt(0.26, 0.37))
    hull.addQuadCurve(to: pt(0.10, 0.50), control: pt(0.14, 0.39))
    hull.closeSubpath()
    ctx.addPath(hull); ctx.fillPath()

    // Ferryman: hooded robe standing toward the stern, facing the bow, hood peaked.
    let robe = CGMutablePath()
    robe.move(to: pt(0.52, 0.43))
    robe.addLine(to: pt(0.68, 0.43))
    robe.addQuadCurve(to: pt(0.655, 0.64), control: pt(0.685, 0.55))
    robe.addQuadCurve(to: pt(0.615, 0.79), control: pt(0.66, 0.73))
    robe.addQuadCurve(to: pt(0.56, 0.705), control: pt(0.575, 0.77))
    robe.addQuadCurve(to: pt(0.545, 0.62), control: pt(0.545, 0.66))
    robe.addQuadCurve(to: pt(0.52, 0.43), control: pt(0.52, 0.52))
    robe.closeSubpath()
    ctx.addPath(robe); ctx.fillPath()

    // Pole beside the figure, down into the water, with the arm reaching for it.
    ctx.setStrokeColor(silhouette)
    ctx.setLineWidth(max(len(0.02), 1))
    ctx.move(to: pt(0.81, 0.88)); ctx.addLine(to: pt(0.48, 0.22)); ctx.strokePath()
    ctx.setLineWidth(max(len(0.034), 1))
    ctx.move(to: pt(0.62, 0.62)); ctx.addLine(to: pt(0.70, 0.66)); ctx.strokePath()

    // Lantern on a post at the bow.
    ctx.setLineWidth(max(len(0.012), 1))
    ctx.move(to: pt(0.20, 0.47)); ctx.addLine(to: pt(0.20, 0.63)); ctx.addLine(to: pt(0.25, 0.63)); ctx.strokePath()
    let lantern = pt(0.25, 0.585)
    let glow = CGGradient(colorsSpace: nil, colors: [color(0xFFD9A0, 0.9), color(0xFFB057, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: lantern, startRadius: 0, endCenter: lantern, endRadius: len(0.11), options: [])
    ctx.setFillColor(color(0xFFE7BD))
    let lanternSize = max(len(0.035), 1.5)
    ctx.fill(CGRect(x: lantern.x - lanternSize / 2, y: lantern.y - lanternSize * 0.7, width: lanternSize, height: lanternSize * 1.4))

    ctx.restoreGState()
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var images: [[String: String]] = []
for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = size * scale
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, render(px), nil)
    CGImageDestinationFinalize(dest)
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
}
let json = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Contents.json"))
