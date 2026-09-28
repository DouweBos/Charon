// DesignSystem/CharonMark.swift
// Charon
//
// The app's mark: the ferryman in his boat against a low moon. Same geometry as the app icon
// (scripts/render-icon.swift), in unit coordinates with y pointing down.

import SwiftUI

struct CharonMark: View {
    /// Draws the rounded-square backdrop, like the app icon. Off to place the mark on another surface.
    var showsBackground = true

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: frame.minX + x * side, y: frame.minY + y * side) }

            if showsBackground {
                let backdrop = Path(roundedRect: frame, cornerRadius: side * 0.225, style: .continuous)
                context.fill(backdrop, with: .color(Theme.markBackground))
                context.clip(to: backdrop)
            }
            let moon = CGRect(x: frame.minX + 0.2 * side, y: frame.minY + 0.12 * side, width: 0.6 * side, height: 0.6 * side)
            context.fill(Path(ellipseIn: moon), with: .color(Theme.markMoon))

            var hull = Path()
            hull.move(to: point(0.12, 0.62))
            hull.addQuadCurve(to: point(0.88, 0.62), control: point(0.5, 0.70))
            hull.addQuadCurve(to: point(0.12, 0.62), control: point(0.5, 0.86))
            hull.closeSubpath()

            var figure = Path()
            figure.move(to: point(0.42, 0.66))
            figure.addQuadCurve(to: point(0.52, 0.27), control: point(0.42, 0.36))
            figure.addQuadCurve(to: point(0.62, 0.66), control: point(0.62, 0.36))
            figure.closeSubpath()

            var pole = Path()
            pole.move(to: point(0.72, 0.16))
            pole.addLine(to: point(0.38, 0.88))

            let silhouette = GraphicsContext.Shading.color(Theme.markSilhouette)
            context.fill(hull, with: silhouette)
            context.fill(figure, with: silhouette)
            context.stroke(pole, with: silhouette, style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 30) {
        CharonMark().frame(width: 150)
        CharonMark().frame(width: 32)
        CharonMark(showsBackground: false).frame(width: 80)
    }
    .padding()
    .background(Theme.background)
}
