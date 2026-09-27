// Views/Ferry/FerryRecordRow.swift
// Charon

import CharonKit
import SwiftUI

struct FerryRecordRow: View {
    @Environment(FerryViewModel.self) private var ferry
    let record: FerryRecord
    let status: FerryStatus

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
                Text("on \(record.shore.name)").font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
            actions
        }
        .card(padding: Theme.Spacing.md)
        .contextMenu {
            Button("Reveal in Finder", systemImage: "folder") { SystemIntegration.revealInFinder(record.originalPath) }
            if case .broken = status {
                Button("Forget", systemImage: "minus.circle", role: .destructive) { ferry.forget(record) }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .ferried:
            Button("Bring Home") { ferry.bringHome(record) }
                .disabled(ferry.operation != nil)
        case .relocated:
            Button("Relink") { ferry.relink(record) }
        case .broken:
            Button("Forget", role: .destructive) { ferry.forget(record) }
        case .stranded, .inProgress:
            EmptyView()
        }
    }

    private var badge: StatusBadge {
        switch status {
        case .ferried: StatusBadge(title: "Ferried", symbol: "checkmark.circle.fill", tone: .positive)
        case .stranded: StatusBadge(title: "Stranded", symbol: "exclamationmark.triangle.fill", tone: .caution)
        case .relocated: StatusBadge(title: "Relocated", symbol: "arrow.triangle.branch", tone: .caution)
        case .broken: StatusBadge(title: "Broken", symbol: "xmark.octagon.fill", tone: .negative)
        case .inProgress(let phase):
            StatusBadge(title: phase.isReturning ? "Coming home" : "Crossing", symbol: "arrow.triangle.2.circlepath", tone: .neutral)
        }
    }

    private var detail: String? {
        switch status {
        case .stranded: "\(record.shore.name) is unplugged. The folder is unavailable until it's back."
        case .relocated(let mount): "\(record.shore.name) is now mounted at \(mount.path). Relink to reconnect."
        case .broken(let reason): reason
        case .inProgress: record.lastError ?? "Interrupted. Charon finishes or rolls this back when the drive is available."
        case .ferried: nil
        }
    }
}
