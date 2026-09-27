// DesignSystem/Breadcrumb.swift
// Charon

import SwiftUI

struct Breadcrumb: View {
    struct Crumb: Identifiable, Hashable {
        var id: String
        var title: String
    }

    let crumbs: [Crumb]
    let onSelect: (Crumb) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                let isLast = index == crumbs.count - 1
                Button(crumb.title) { onSelect(crumb) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: isLast ? .semibold : .regular))
                    .foregroundStyle(isLast ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .disabled(isLast)
            }
        }
    }
}

#Preview {
    Breadcrumb(crumbs: [
        .init(id: "/", title: "Macintosh HD"), .init(id: "/Users", title: "Users"), .init(id: "/Users/me", title: "me")
    ]) { _ in }
    .padding()
    .background(Theme.background)
}
