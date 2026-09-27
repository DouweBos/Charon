// Views/Offload/OffloadRecordRow.swift
// Charon

import CharonKit
import SwiftUI

struct OffloadRecordRow: View {
    @Environment(OffloadViewModel.self) private var offload
    let record: OffloadRecord
    let status: OffloadStatus

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(record.name).font(.system(size: 14, weight: .semibold))
                    badge
                }
                Text(record.originalPath)
                    .font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteSize.format(record.bytes)).font(.system(size: 14, weight: .medium, design: .monospaced))
                Text("on \(record.drive.name)").font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
            actions
        }
        .card(padding: Theme.Spacing.md)
        .contextMenu {
            Button("Reveal in Finder", systemImage: "folder") { SystemIntegration.revealInFinder(record.originalPath) }
            if case .broken = status {
                Button("Forget", systemImage: "minus.circle", role: .destructive) { offload.forget(record) }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .offloaded:
            Button("Move Back") { offload.moveBack(record) }
                .disabled(offload.operation != nil)
        case .remounted:
            Button("Relink") { offload.relink(record) }
        case .broken:
            Button("Forget", role: .destructive) { offload.forget(record) }
        case .disconnected, .inProgress:
            EmptyView()
        }
    }

    private var badge: StatusBadge {
        switch status {
        case .offloaded: StatusBadge(title: "Offloaded", symbol: "checkmark.circle.fill", tone: .positive)
        case .disconnected: StatusBadge(title: "Disconnected", symbol: "exclamationmark.triangle.fill", tone: .caution)
        case .remounted: StatusBadge(title: "Drive moved", symbol: "arrow.triangle.branch", tone: .caution)
        case .broken: StatusBadge(title: "Broken", symbol: "xmark.octagon.fill", tone: .negative)
        case .inProgress(let phase):
            StatusBadge(title: phase.isReturning ? "Moving back" : "In progress", symbol: "arrow.triangle.2.circlepath", tone: .neutral)
        }
    }

    private var detail: String? {
        switch status {
        case .disconnected: "\(record.drive.name) is unplugged. The folder is unavailable until it's back."
        case .remounted(let mount): "\(record.drive.name) is now mounted at \(mount.path). Relink to reconnect."
        case .broken(let reason): reason
        case .inProgress: record.lastError ?? "Interrupted. Charon finishes or rolls this back when the drive is available."
        case .offloaded: nil
        }
    }
}
