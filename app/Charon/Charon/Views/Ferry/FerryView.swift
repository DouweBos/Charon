// Views/Ferry/FerryView.swift
// Charon
//
// Everything on the other shore: Obols reclaimed, the chosen drive, and every ferried directory's status.

import CharonKit
import SwiftUI

struct FerryView: View {
    @Environment(AppModel.self) private var model
    @Environment(FerryViewModel.self) private var ferry
    @Environment(VolumesViewModel.self) private var volumes

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                obolCard
                ShoreCard()
            }
            .fixedSize(horizontal: false, vertical: true)

            if let operation = ferry.operation {
                ProgressStrip(
                    title: operationTitle(operation),
                    detail: operation.progress.map { "\(ByteSize.format($0.bytesDone)) of \(ByteSize.format($0.bytesTotal))" } ?? "Preparing…",
                    fraction: operation.progress?.fraction,
                    onCancel: { ferry.cancelOperation() }
                )
                .card()
            }

            HStack {
                Text("Ferried").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Ferry a Folder…", systemImage: "ferry") {
                    if let url = SystemIntegration.chooseDirectory(message: "Choose a folder to ferry to the Other Shore.") {
                        model.requestFerry(path: url.path, knownBytes: nil)
                    }
                }
            }

            if ferry.records.isEmpty {
                ContentUnavailableView(
                    "Nothing has crossed yet", systemImage: "water.waves",
                    description: Text(
                        "Right-click a folder in Analyze and choose Ferry to Other Shore. "
                            + "Charon copies it, verifies every byte, and leaves a symlink behind."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(ferry.records) { record in
                            FerryRecordRow(record: record, status: ferry.status(of: record))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .task { await ferry.refresh() }
    }

    private var obolCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Obols", systemImage: "centsign.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(ByteSize.format(ferry.obols)).font(.statValue)
                Text("reclaimed").font(.statUnit).foregroundStyle(Theme.textSecondary)
            }
            Text(summary)
                .font(.monoCaption)
                .foregroundStyle(ferry.strandedCount > 0 ? Theme.warning : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private var summary: String {
        let count = ferry.records.count
        let base = "\(count) \(count == 1 ? "directory" : "directories") across the Styx"
        return ferry.strandedCount > 0 ? base + " · \(ferry.strandedCount) stranded" : base
    }

    private func operationTitle(_ operation: FerryOperation) -> String {
        let stage = operation.progress?.stage.rawValue.capitalized ?? "Starting"
        switch operation.kind {
        case .ferry: return "Ferrying \(operation.name) · \(stage)"
        case .bringHome: return "Bringing \(operation.name) home · \(stage)"
        }
    }
}

struct ShoreCard: View {
    @Environment(FerryViewModel.self) private var ferry
    @Environment(VolumesViewModel.self) private var volumes

    private var shore: VolumeInfo? { volumes.volume(ferry.shoreVolumeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Other Shore", systemImage: "externaldrive.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.statDisk)
            Menu {
                ForEach(volumes.shoreCandidates) { volume in
                    Button("\(volume.name) · \(ByteSize.format(volume.availableBytes)) free") { ferry.selectShore(volume.id) }
                }
                if volumes.shoreCandidates.isEmpty {
                    Text("Connect an external drive")
                }
            } label: {
                Text(shore?.name ?? (ferry.shoreVolumeID == nil ? "Choose a drive" : "Not connected"))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            if let shore {
                UsageBar(used: shore.usedBytes, total: shore.totalBytes, width: 110)
                if !shore.preservesMetadata {
                    Text("\(shore.fileSystem.uppercased()) drops permissions; APFS is recommended.")
                        .font(.monoCaption).foregroundStyle(Theme.warning)
                }
            } else {
                Text(volumes.shoreCandidates.isEmpty ? "Plug in an external drive." : "Pick where ferried folders go.")
                    .font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}
