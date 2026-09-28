// Renders the app icon into an .appiconset: swift scripts/render-icon.swift Charon/Assets.xcassets/AppIcon.appiconset
// Same geometry as CharonMark (DesignSystem): ferryman, boat and pole against a moon. Unit coordinates, y down.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> CGImage {
    let size = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip so the unit coordinates match SwiftUI's (y down).
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824/1024 body with ~185 corner radius.
    let inset = size * 100 / 1024
    let side = size - 2 * inset
    let frame = CGRect(x: inset, y: inset, width: side, height: side)
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: frame.minX + x * side, y: frame.minY + y * side) }

    let backdrop = CGPath(roundedRect: frame, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: size * 0.01), blur: size * 0.025, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(backdrop); ctx.setFillColor(color(0x171C27)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(backdrop); ctx.clip()

    ctx.setFillColor(color(0xE3A574))
    ctx.fillEllipse(in: CGRect(x: frame.minX + 0.2 * side, y: frame.minY + 0.12 * side, width: 0.6 * side, height: 0.6 * side))

    ctx.setFillColor(color(0x0A0C11))
    ctx.move(to: point(0.12, 0.62))
    ctx.addQuadCurve(to: point(0.88, 0.62), control: point(0.5, 0.70))
    ctx.addQuadCurve(to: point(0.12, 0.62), control: point(0.5, 0.86))
    ctx.closePath(); ctx.fillPath()

    ctx.move(to: point(0.42, 0.66))
    ctx.addQuadCurve(to: point(0.52, 0.27), control: point(0.42, 0.36))
    ctx.addQuadCurve(to: point(0.62, 0.66), control: point(0.62, 0.36))
    ctx.closePath(); ctx.fillPath()

    ctx.setStrokeColor(color(0x0A0C11))
    ctx.setLineWidth(side * 0.035)
    ctx.setLineCap(.round)
    ctx.move(to: point(0.72, 0.16)); ctx.addLine(to: point(0.38, 0.88)); ctx.strokePath()
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var images: [[String: String]] = []
for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, render(size * scale), nil)
    CGImageDestinationFinalize(dest)
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
}
let json = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Contents.json"))
