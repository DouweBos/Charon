// Renders the app icon into an .appiconset: swift scripts/render-icon.swift Charon/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> CGImage {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: 824/1024 body with ~185 corner radius.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x1D1D1F)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [color(0x2C2C31), color(0x141416)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Planet
    let d = body.width * 0.62
    let planet = CGRect(x: body.midX - d / 2, y: body.midY - d / 2 + body.height * 0.02, width: d, height: d)
    ctx.saveGState()
    ctx.addEllipse(in: planet); ctx.clip()
    ctx.setFillColor(color(0xF1DDC4)); ctx.fill(planet)
    let bands: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.06, 0.5), (0.3, 0.09, 0.8), (0.42, 0.04, 0.45), (0.55, 0.11, 0.9), (0.66, 0.05, 0.5), (0.76, 0.08, 0.75), (0.87, 0.05, 0.45)]
    for (c, t, a) in bands {
        let y = planet.maxY - planet.height * c
        ctx.setFillColor(color(0xC48856, a))
        ctx.fill(CGRect(x: planet.minX, y: y - planet.height * t / 2, width: planet.width, height: planet.height * t))
    }
    ctx.setFillColor(color(0x6B4127, 0.6))
    ctx.fillEllipse(in: CGRect(x: planet.minX + planet.width * 0.52, y: planet.maxY - planet.height * 0.68, width: planet.width * 0.16, height: planet.height * 0.08))
    let shade = CGGradient(colorsSpace: nil, colors: [color(0x6B4127, 0), color(0x2A170C, 0.85)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(shade, startCenter: CGPoint(x: planet.minX + d * 0.38, y: planet.maxY - d * 0.32), startRadius: d * 0.2,
                           endCenter: CGPoint(x: planet.minX + d * 0.38, y: planet.maxY - d * 0.32), endRadius: d * 0.75, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Orbit ring passing behind/in front, hinting at motion between places.
    ctx.saveGState()
    ctx.translateBy(x: planet.midX, y: planet.midY)
    ctx.rotate(by: -0.35)
    let ring = CGRect(x: -d * 0.78, y: -d * 0.16, width: d * 1.56, height: d * 0.32)
    ctx.setStrokeColor(color(0xE3A574, 0.9)); ctx.setLineWidth(max(s * 0.012, 1))
    ctx.strokeEllipse(in: ring)
    ctx.restoreGState()
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
let json = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Contents.json"))
