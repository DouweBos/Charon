// Views/Offload/OffloadView.swift
// Charon
//
// Offloaded folders: space freed, the chosen drive, and every offloaded directory's status.

import CharonKit
import SwiftUI

struct OffloadView: View {
    @Environment(AppModel.self) private var model
    @Environment(OffloadViewModel.self) private var offload
    @Environment(VolumesViewModel.self) private var volumes

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                obolCard
                DriveCard()
            }
            .fixedSize(horizontal: false, vertical: true)

            if let operation = offload.operation {
                ProgressStrip(
                    title: operationTitle(operation),
                    detail: operation.progress.map { "\(ByteSize.format($0.bytesDone)) of \(ByteSize.format($0.bytesTotal))" } ?? "Preparing…",
                    fraction: operation.progress?.fraction,
                    onCancel: { offload.cancelOperation() }
                )
                .card()
            }

            HStack {
                Text("Offloaded").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Offload a Folder…", systemImage: "externaldrive.badge.plus") {
                    if let url = SystemIntegration.chooseDirectory(message: "Choose a folder to offload to the external drive.") {
                        model.requestOffload(path: url.path, knownBytes: nil)
                    }
                }
            }

            if offload.records.isEmpty {
                ContentUnavailableView(
                    "Nothing has crossed yet", systemImage: "water.waves",
                    description: Text(
                        "Right-click a folder in Analyze and choose Move to External Drive. "
                            + "Charon copies it, verifies every byte, and leaves a symlink behind."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(offload.records) { record in
                            OffloadRecordRow(record: record, status: offload.status(of: record))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .task { await offload.refresh() }
    }

    private var obolCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Space freed", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(ByteSize.format(offload.freedBytes)).font(.statValue)
                Text("reclaimed").font(.statUnit).foregroundStyle(Theme.textSecondary)
            }
            Text(summary)
                .font(.monoCaption)
                .foregroundStyle(offload.disconnectedCount > 0 ? Theme.warning : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private var summary: String {
        let count = offload.records.count
        let base = "\(count) \(count == 1 ? "directory" : "directories") on external drives"
        return offload.disconnectedCount > 0 ? base + " · \(offload.disconnectedCount) disconnected" : base
    }

    private func operationTitle(_ operation: OffloadOperation) -> String {
        let stage = operation.progress?.stage.rawValue.capitalized ?? "Starting"
        switch operation.kind {
        case .offload: return "Offloading \(operation.name) · \(stage)"
        case .moveBack: return "Moving \(operation.name) back · \(stage)"
        }
    }
}

struct DriveCard: View {
    @Environment(OffloadViewModel.self) private var offload
    @Environment(VolumesViewModel.self) private var volumes

    private var drive: VolumeInfo? { volumes.volume(offload.driveVolumeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("External Drive", systemImage: "externaldrive.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.statDisk)
            Menu {
                ForEach(volumes.driveCandidates) { volume in
                    Button("\(volume.name) · \(ByteSize.format(volume.availableBytes)) free") { offload.selectDrive(volume.id) }
                }
                if volumes.driveCandidates.isEmpty {
                    Text("Connect an external drive")
                }
            } label: {
                Text(drive?.name ?? (offload.driveVolumeID == nil ? "Choose a drive" : "Not connected"))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            if let drive {
                UsageBar(used: drive.usedBytes, total: drive.totalBytes, width: 110)
                if !drive.preservesMetadata {
                    Text("\(drive.fileSystem.uppercased()) drops permissions; APFS is recommended.")
                        .font(.monoCaption).foregroundStyle(Theme.warning)
                }
            } else {
                Text(volumes.driveCandidates.isEmpty ? "Plug in an external drive." : "Pick where offloaded folders go.")
                    .font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}
