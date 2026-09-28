// DesignSystem/DragChip.swift
// Charon
//
// What follows the pointer while dragging a file or folder, instead of a snapshot of the whole view.

import CharonKit
import SwiftUI

struct DragChip: View {
    let title: String
    let size: Int64
    var symbol = "folder"
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(ByteSize.format(size)).font(.monoCaption).foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: 280)
        .background(Capsule().fill(Theme.surfaceRaised))
        .overlay(Capsule().strokeBorder(Theme.border))
        .fixedSize()
    }
}

extension View {
    /// Drags `path` as a file URL with a `DragChip` preview; nil makes nothing draggable.
    @ViewBuilder
    func fileDrag(path: String?, title: String, size: Int64, isDirectory: Bool = true, tint: Color = Theme.accent) -> some View {
        onDrag {
            guard let path else { return NSItemProvider() }
            return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
        } preview: {
            if path != nil {
                DragChip(title: title, size: size, symbol: isDirectory ? "folder" : "doc", tint: tint)
            }
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        DragChip(title: "DerivedData", size: 42_000_000_000)
        DragChip(title: "a-very-long-file-name-that-keeps-going-and-going.mov", size: 3_200_000_000, symbol: "doc")
    }
    .padding()
    .background(Theme.background)
}
