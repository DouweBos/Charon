// Renders the app icon as an Icon Composer bundle. Run once per app:
//   swift scripts/render-icon.swift Charon/AppIcon.icon
//   swift scripts/render-icon.swift CharonMonitor/AppIcon.icon
// Treemap tiles in amber, on a warm light backdrop for light mode and a charcoal one for dark mode.
// macOS draws the backdrop from icon.json's fill and masks it to the icon shape; the glyph is a full-canvas layer.
// Same geometry as CharonMark (DesignSystem), in unit coordinates with y down.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Palette {
    var top: UInt32, bottom: UInt32, glyphTop: UInt32, glyphBottom: UInt32, shadow: CGFloat
}

let light = Palette(top: 0xFDF9F3, bottom: 0xEDE4D8, glyphTop: 0xF2A05C, glyphBottom: 0xD8672A, shadow: 0.15)
let dark = Palette(top: 0x2A2F3C, bottom: 0x10131A, glyphTop: 0xF6BE82, glyphBottom: 0xE08A45, shadow: 0.25)

/// x, y, width, height of each tile.
let tiles: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (0.14, 0.20, 0.40, 0.60), (0.58, 0.20, 0.28, 0.30), (0.58, 0.54, 0.12, 0.26), (0.74, 0.54, 0.12, 0.26)
]

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// The glyph alone on a transparent 1024 canvas; the whole canvas is the icon's face.
func renderGlyph(_ palette: Palette) -> CGImage {
    let side: CGFloat = 1024
    let ctx = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: side)
    ctx.scaleBy(x: 1, y: -1)
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * side, y: y * side) }
    let glyph = CGMutablePath()
    for (x, y, width, height) in tiles {
        glyph.addPath(CGPath(roundedRect: CGRect(origin: point(x, y), size: CGSize(width: width * side, height: height * side)),
                             cornerWidth: side * 0.05, cornerHeight: side * 0.05, transform: nil))
    }
    ctx.addPath(glyph); ctx.clip()
    let fill = CGGradient(colorsSpace: nil, colors: [color(palette.glyphTop), color(palette.glyphBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fill, start: point(0.5, 0.15), end: point(0.5, 0.9), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    return ctx.makeImage()!
}

func srgb(_ hex: UInt32) -> String {
    let parts = [16, 8, 0].map { String(format: "%.5f", Double((hex >> UInt32($0)) & 0xFF) / 255) }
    return "srgb:" + parts.joined(separator: ",") + ",1.00000"
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = out.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
for (palette, name) in [(light, "tiles.png"), (dark, "tiles-dark.png")] {
    let dest = CGImageDestinationCreateWithURL(assets.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, renderGlyph(palette), nil)
    CGImageDestinationFinalize(dest)
}

let document: [String: Any] = [
    "fill-specializations": [
        ["value": ["linear-gradient": [srgb(light.top), srgb(light.bottom)]]],
        ["appearance": "dark", "value": ["linear-gradient": [srgb(dark.top), srgb(dark.bottom)]]]
    ],
    "groups": [[
        "layers": [[
            "name": "tiles",
            "image-name-specializations": [
                ["value": "tiles.png"],
                ["appearance": "dark", "value": "tiles-dark.png"]
            ]
        ]],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "translucency": ["enabled": false, "value": 0.5]
    ]],
    "supported-platforms": ["squares": ["macOS"]]
]
let json = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("icon.json"))
