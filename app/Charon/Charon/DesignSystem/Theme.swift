// DesignSystem/Theme.swift
// Charon
//
// Every color the UI uses. Values live in the asset catalog with light and dark variants.

import SwiftUI

enum Theme {
    static let background = Color(.background)
    static let surface = Color(.surface)
    static let surfaceRaised = Color(.surfaceRaised)
    static let border = Color(.border)
    static let textPrimary = Color(.textPrimary)
    static let textSecondary = Color(.textSecondary)
    static let textOnTile = Color(.textOnTile)
    static let pillSelected = Color(.pillSelected)
    static let pillSelectedText = Color(.pillSelectedText)
    static let accent = Color.accentColor
    static let success = Color(.success)
    static let warning = Color(.warning)
    static let danger = Color(.danger)

    static let externalDrive = Color(.externalDrive)

    static let markBackgroundTop = Color(.markBackgroundTop)
    static let markBackgroundBottom = Color(.markBackgroundBottom)
    static let markGlyphTop = Color(.markGlyphTop)
    static let markGlyphBottom = Color(.markGlyphBottom)

    static let treemapPalette: [Color] = [
        Color(.treemap1), Color(.treemap2), Color(.treemap3), Color(.treemap4),
        Color(.treemap5), Color(.treemap6), Color(.treemap7), Color(.treemap8)
    ]
    static let treemapNeutral = Color(.treemapNeutral)

    static func treemapColor(_ index: Int) -> Color {
        treemapPalette[index % treemapPalette.count]
    }

    /// Containers recede so their nested tiles read as the content; deeper leaves get slightly lighter.
    static func treemapFill(colorIndex: Int, depth: Int, isContainer: Bool, isNeutral: Bool) -> Color {
        let base = isNeutral ? treemapNeutral : treemapColor(colorIndex)
        if isContainer { return base.opacity(0.32) }
        return base.opacity(max(1 - 0.14 * Double(depth - 1), 0.6))
    }

    /// Inner rings solid, outer rings fading toward the background, like depth in the treemap.
    static func sunburstFill(colorIndex: Int, depth: Int, isNeutral: Bool) -> Color {
        let base = isNeutral ? treemapNeutral : treemapColor(colorIndex)
        return base.opacity(max(1 - 0.12 * Double(depth - 1), 0.4))
    }

    static let tileHoverStroke = textOnTile.opacity(0.85)
    static let tileSecondaryText = textOnTile.opacity(0.75)
    static let tileHeaderText = textPrimary
    static let sparklineFillOpacity = 0.25
    static let subtleFill = textSecondary.opacity(0.12)
    static let bannerFill = warning.opacity(0.14)
    static let dangerFill = danger.opacity(0.12)
    static let track = textSecondary.opacity(0.2)

    enum Radius {
        static let card: CGFloat = 14
        static let tile: CGFloat = 6
        static let pill: CGFloat = 20
        static let row: CGFloat = 10
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

extension Font {
    static let statValue = Font.system(size: 30, weight: .medium, design: .rounded)
    static let statUnit = Font.system(size: 15, weight: .medium, design: .rounded)
    static let capacityTitle = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let monoCaption = Font.system(size: 12, weight: .regular, design: .monospaced)
}
