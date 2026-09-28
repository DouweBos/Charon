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
                spaceFreedCard
                DriveCard()
            }
            .fixedSize(horizontal: false, vertical: true)

            if let problem = offload.manifestProblem {
                Banner(symbol: "exclamationmark.octagon", message: problem, tone: .negative)
            }
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if offload.records.isEmpty {
                        Text("Nothing offloaded yet. Charon copies a folder to the external drive, checks every byte, "
                             + "then leaves a link in its place so apps still find it.")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(offload.records) { record in
                        OffloadRecordRow(record: record, status: offload.status(of: record))
                    }
                    OffloadSuggestionsSection()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .task { await offload.refresh() }
    }

    private var spaceFreedCard: some View {
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
        case .check: return "Checking \(operation.name) on the drive"
        }
    }
}

struct DriveCard: View {
    @Environment(OffloadViewModel.self) private var offload
    @Environment(VolumesViewModel.self) private var volumes

    private var drive: VolumeInfo? { volumes.volume(offload.driveVolumeID) }

    private func showDriveMenu() {
        let items = volumes.driveCandidates.map { volume in
            PopUpMenu.Item(
                title: "\(volume.name) · \(ByteSize.format(volume.availableBytes)) free", symbol: "externaldrive",
                isChecked: volume.id == offload.driveVolumeID
            ) { offload.selectDrive(volume.id) }
        }
        let empty = PopUpMenu.Item(title: "Connect an external drive", symbol: "cable.connector") {}
        PopUpMenu.show([PopUpMenu.Section(title: "External drives", items: items.isEmpty ? [empty] : items)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("External Drive", systemImage: "externaldrive.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.statDisk)
            Button(action: showDriveMenu) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(drive?.name ?? (offload.driveVolumeID == nil ? "Choose a drive" : "Not connected"))
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
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
