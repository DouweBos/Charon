// DesignSystem/CharonMark.swift
// Charon
//
// The app's mark: treemap tiles in amber. Same geometry as the app icon (scripts/render-icon.swift), with colors
// that follow light and dark mode like the icon does.

import SwiftUI

struct CharonMark: View {
    /// Draws the rounded-square backdrop, like the app icon. Off to place the tiles on another surface.
    var showsBackground = true

    /// Tiles in unit coordinates, y down.
    private static let tiles = [
        CGRect(x: 0.14, y: 0.20, width: 0.40, height: 0.60), CGRect(x: 0.58, y: 0.20, width: 0.28, height: 0.30),
        CGRect(x: 0.58, y: 0.54, width: 0.12, height: 0.26), CGRect(x: 0.74, y: 0.54, width: 0.12, height: 0.26)
    ]

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)

            if showsBackground {
                let backdrop = Path(roundedRect: frame, cornerRadius: side * 0.225, style: .continuous)
                context.fill(backdrop, with: .linearGradient(
                    Gradient(colors: [Theme.markBackgroundTop, Theme.markBackgroundBottom]),
                    startPoint: CGPoint(x: frame.midX, y: frame.minY), endPoint: CGPoint(x: frame.midX, y: frame.maxY)
                ))
            }
            var glyph = Path()
            for tile in Self.tiles {
                let rect = CGRect(x: frame.minX + tile.minX * side, y: frame.minY + tile.minY * side,
                                  width: tile.width * side, height: tile.height * side)
                glyph.addRoundedRect(in: rect, cornerSize: CGSize(width: side * 0.05, height: side * 0.05), style: .continuous)
            }
            context.fill(glyph, with: .linearGradient(
                Gradient(colors: [Theme.markGlyphTop, Theme.markGlyphBottom]),
                startPoint: CGPoint(x: frame.midX, y: frame.minY + 0.15 * side),
                endPoint: CGPoint(x: frame.midX, y: frame.minY + 0.9 * side)
            ))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview("Light") {
    HStack(spacing: 30) {
        CharonMark().frame(width: 150)
        CharonMark().frame(width: 32)
        CharonMark(showsBackground: false).frame(width: 80)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HStack(spacing: 30) {
        CharonMark().frame(width: 150)
        CharonMark().frame(width: 32)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
