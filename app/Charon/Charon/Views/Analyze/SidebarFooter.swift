// Views/Analyze/SidebarFooter.swift
// Charon

import CharonKit
import SwiftUI

struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(VolumesViewModel.self) private var volumes
    let volume: VolumeInfo

    /// Like DaisyDisk's legend footer: what's free now, and what macOS can free on demand.
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack {
                Label("Free space", systemImage: "circle").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(ByteSize.format(max(volume.availableBytes - volume.purgeableBytes, 0))).font(.monoCaption)
            }
            HStack {
                Label("Free + purgeable", systemImage: "circle.dashed").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(ByteSize.format(volume.availableBytes)).font(.monoCaption)
            }
            if volume.id == volumes.bootVolume?.id, let trash = model.trashBytes {
                TrashLine(bytes: trash) { model.requestEmptyTrash() }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, Theme.Spacing.md)
    }
}

/// Sidebar footer line for the Trash; an Empty button appears on hover.
private struct TrashLine: View {
    let bytes: Int64
    let onEmpty: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Label("Trash", systemImage: bytes > 0 ? "trash" : "trash.slash").foregroundStyle(Theme.textSecondary)
            Spacer()
            if isHovered, bytes > 0 {
                Button("Empty", action: onEmpty)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
            Text(ByteSize.format(bytes)).font(.monoCaption)
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .help(bytes > 0 ? "Space the Trash takes until it's emptied" : "The Trash is empty")
    }
}
