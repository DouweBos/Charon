// DesignSystem/Sparkline.swift
// Charon
//
// Tiny history chart for stat cards: a filled line, or bars for bursty values like CPU.

import SwiftUI

struct Sparkline: View {
    enum Style { case line, bars }

    /// Values in 0...1, oldest first.
    let values: [Double]
    let color: Color
    var style: Style = .line

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            switch style {
            case .bars: drawBars(context, size)
            case .line: drawLine(context, size)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBars(_ context: GraphicsContext, _ size: CGSize) {
        let count = values.count
        let slot = size.width / CGFloat(count)
        for (index, value) in values.enumerated() {
            let height = max(size.height * CGFloat(min(max(value, 0), 1)), 2)
            let rect = CGRect(x: CGFloat(index) * slot + 1, y: size.height - height, width: max(slot - 2, 1), height: height)
            context.fill(Path(rect), with: .color(color))
        }
    }

    private func drawLine(_ context: GraphicsContext, _ size: CGSize) {
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : size.width
        func point(_ index: Int) -> CGPoint {
            let value = CGFloat(min(max(values[index], 0), 1))
            return CGPoint(x: CGFloat(index) * step, y: size.height - value * (size.height - 2) - 1)
        }
        var line = Path()
        line.move(to: point(0))
        for index in values.indices.dropFirst() { line.addLine(to: point(index)) }
        if values.count == 1 { line.addLine(to: CGPoint(x: size.width, y: point(0).y)) }

        var fill = line
        fill.addLine(to: CGPoint(x: values.count == 1 ? size.width : point(values.count - 1).x, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()

        context.fill(fill, with: .linearGradient(
            Gradient(colors: [color.opacity(Theme.sparklineFillOpacity), .clear]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
        ))
        context.stroke(line, with: .color(color), lineWidth: 1.5)
    }
}

#Preview {
    VStack(spacing: 20) {
        Sparkline(values: [0.1, 0.2, 0.15, 0.4, 0.35, 0.3, 0.5, 0.2, 0.1], color: Theme.statCPU, style: .bars)
        Sparkline(values: [0.48, 0.49, 0.47, 0.5, 0.48], color: Theme.statMemory)
        Sparkline(values: [0.28], color: Theme.statDisk)
        Sparkline(values: [], color: Theme.statNetwork)
    }
    .frame(width: 240, height: 200)
    .padding()
    .background(Theme.surface)
}
