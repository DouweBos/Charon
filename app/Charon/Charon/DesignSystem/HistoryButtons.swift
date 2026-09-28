// DesignSystem/HistoryButtons.swift
// Charon
//
// Back and forward, as a pair of round buttons.

import SwiftUI

struct HistoryButtons: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            button("chevron.left", label: "Back", help: "Back (⌘[)", enabled: canGoBack, action: onBack)
            button("chevron.right", label: "Forward", help: "Forward (⌘])", enabled: canGoForward, action: onForward)
        }
    }

    private func button(_ symbol: String, label: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary)
                .background(Circle().fill(Theme.subtleFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(label)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        HistoryButtons(canGoBack: true, canGoForward: true, onBack: {}, onForward: {})
        HistoryButtons(canGoBack: true, canGoForward: false, onBack: {}, onForward: {})
        HistoryButtons(canGoBack: false, canGoForward: false, onBack: {}, onForward: {})
    }
    .padding()
    .background(Theme.background)
}
