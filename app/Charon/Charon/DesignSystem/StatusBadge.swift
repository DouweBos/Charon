// DesignSystem/StatusBadge.swift
// Charon

import SwiftUI

struct StatusBadge: View {
    enum Tone { case positive, caution, negative, neutral }

    let title: String
    let symbol: String
    let tone: Tone

    private var color: Color {
        switch tone {
        case .positive: Theme.success
        case .caution: Theme.warning
        case .negative: Theme.danger
        case .neutral: Theme.textSecondary
        }
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

#Preview {
    VStack(alignment: .leading) {
        StatusBadge(title: "Offloaded", symbol: "checkmark.circle.fill", tone: .positive)
        StatusBadge(title: "Disconnected", symbol: "exclamationmark.triangle.fill", tone: .caution)
        StatusBadge(title: "Broken", symbol: "xmark.octagon.fill", tone: .negative)
        StatusBadge(title: "Copying", symbol: "arrow.triangle.2.circlepath", tone: .neutral)
    }
    .padding()
    .background(Theme.surface)
}
