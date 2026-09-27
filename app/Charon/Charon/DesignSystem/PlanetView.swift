// DesignSystem/PlanetView.swift
// Charon
//
// The disk "planet": a banded gas giant drawn procedurally so it scales and follows the theme.

import SwiftUI

struct PlanetView: View {
    /// Latitude bands; positions are fractions of the planet's height.
    private struct Band {
        var center: CGFloat
        var thickness: CGFloat
        var strength: Double
    }

    private static let bands = [
        Band(center: 0.18, thickness: 0.06, strength: 0.5), Band(center: 0.3, thickness: 0.09, strength: 0.8),
        Band(center: 0.42, thickness: 0.04, strength: 0.45), Band(center: 0.55, thickness: 0.11, strength: 0.9),
        Band(center: 0.66, thickness: 0.05, strength: 0.5), Band(center: 0.76, thickness: 0.08, strength: 0.75),
        Band(center: 0.87, thickness: 0.05, strength: 0.45)
    ]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let circle = Path(ellipseIn: rect)
            context.clip(to: circle)
            context.fill(circle, with: .color(Theme.planetLight))

            for band in Self.bands {
                let (center, thickness, strength) = (band.center, band.thickness, band.strength)
                let band = CGRect(x: rect.minX, y: rect.minY + rect.height * (center - thickness / 2),
                                  width: rect.width, height: rect.height * thickness)
                context.fill(Path(band), with: .color(Theme.planetBand.opacity(strength)))
            }
            let spot = CGRect(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.6,
                              width: rect.width * 0.16, height: rect.height * 0.08)
            context.fill(Path(ellipseIn: spot), with: .color(Theme.planetDark.opacity(0.6)))

            // Terminator shading gives it volume.
            context.fill(circle, with: .radialGradient(
                Gradient(colors: [.clear, Theme.planetDark.opacity(0.75)]),
                center: CGPoint(x: rect.width * 0.38, y: rect.height * 0.32),
                startRadius: rect.width * 0.2, endRadius: rect.width * 0.72
            ))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 30) {
        PlanetView().frame(width: 160)
        PlanetView().frame(width: 48)
    }
    .padding()
    .background(Theme.background)
}
