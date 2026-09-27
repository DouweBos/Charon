// DesignSystem/DirectoryRow.swift
// Charon
//
// Sidebar row: folder icon, name, "size · share", and a chevron when it can be drilled into.

import SwiftUI

struct DirectoryRow: View {
    let name: String
    let detail: String
    var symbol = "folder"
    var tint: Color = Theme.accent
    var isSelected = false
    var showsChevron = true

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(
            isSelected || isHovered ? Theme.surfaceRaised : Theme.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

#Preview {
    VStack(spacing: 6) {
        DirectoryRow(name: "Users", detail: "226.39 GB · 72%")
        DirectoryRow(name: "opt/homebrew", detail: "4.83 GB · 1%", tint: Theme.treemapColor(3), isSelected: true)
        DirectoryRow(name: "Files", detail: "120 MB · <1%", symbol: "doc", showsChevron: false)
    }
    .frame(width: 280)
    .padding()
    .background(Theme.background)
}
