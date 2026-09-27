// DesignSystem/CardSurface.swift
// Charon

import SwiftUI

struct CardSurface: ViewModifier {
    var padding: CGFloat = Theme.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.lg) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

#Preview {
    VStack(alignment: .leading) {
        Text("Card title").foregroundStyle(Theme.textPrimary)
        Text("Secondary").foregroundStyle(Theme.textSecondary)
    }
    .card()
    .padding()
    .background(Theme.background)
}
