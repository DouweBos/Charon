// DesignSystem/CountdownRing.swift
// Charon
//
// Small ring that drains as seconds run out, with the seconds left in the middle.

import SwiftUI

struct CountdownRing: View {
    let remaining: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 3)
            Circle()
                .trim(from: 0, to: Double(remaining) / Double(max(total, 1)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            Text("\(remaining)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: remaining)
        }
        .frame(width: 26, height: 26)
        .accessibilityElement()
        .accessibilityLabel("\(remaining) seconds left")
    }
}

#Preview {
    HStack(spacing: 20) {
        CountdownRing(remaining: 10, total: 10)
        CountdownRing(remaining: 6, total: 10)
        CountdownRing(remaining: 1, total: 10)
    }
    .padding()
    .background(Theme.surface)
}
