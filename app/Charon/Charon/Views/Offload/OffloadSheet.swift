// Views/Offload/OffloadSheet.swift
// Charon
//
// Confirm an offload: preflight blockers and warnings, then progress, then the space freed.

import CharonKit
import SwiftUI

struct OffloadSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(OffloadViewModel.self) private var offload
    @Environment(VolumesViewModel.self) private var volumes

    var body: some View {
        if let request = offload.request {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header(request)
                content(request)
                Spacer(minLength: 0)
                footer(request)
            }
            .padding(Theme.Spacing.xl)
            .frame(width: 520, height: 420)
            .background(Theme.background)
        }
    }

    private func header(_ request: OffloadRequest) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "externaldrive.fill.badge.plus").font(.system(size: 28)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Offload \(URL(fileURLWithPath: request.path).lastPathComponent)")
                    .font(.system(size: 18, weight: .semibold))
                Text(request.path).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func content(_ request: OffloadRequest) -> some View {
        switch request.stage {
        case .checking:
            ProgressStrip(title: "Checking whether it's safe to offload…", detail: "")
        case .review:
            if let report = request.report { review(report, request) }
        case .running:
            let progress = offload.operation?.progress
            ProgressStrip(
                title: (progress?.stage.rawValue.capitalized ?? "Starting") + "…",
                detail: progress.map { "\(ByteSize.format($0.bytesDone)) of \(ByteSize.format($0.bytesTotal))" } ?? "",
                fraction: progress?.fraction,
                onCancel: { offload.cancelOperation() }
            )
            Text("The original stays in place until every file on the external drive is verified.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        case .done(let reclaimed):
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("\(ByteSize.format(reclaimed)) reclaimed", systemImage: "centsign.circle.fill")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                let driveName = model.driveVolume?.name ?? "the external drive"
                Text("It now lives on \(driveName). The symlink keeps every path working while the drive is connected.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        case .failed(let message):
            Banner(symbol: "xmark.octagon", message: message, tone: .negative)
        }
    }

    private func review(_ report: PreflightReport, _ request: OffloadRequest) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xl) {
                fact("Size", ByteSize.format(report.bytes))
                VStack(alignment: .leading, spacing: 2) {
                    Text("External Drive").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    drivePicker
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(report.blockers) { issue in
                        Banner(symbol: "xmark.octagon", message: issue.message, tone: .negative)
                    }
                    ForEach(report.warnings) { issue in
                        Banner(symbol: "exclamationmark.triangle", message: issue.message)
                    }
                    if report.issues.isEmpty {
                        Label("No problems found.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    }
                }
            }
            if report.canOffload, !report.warnings.isEmpty {
                Toggle("I understand the warnings", isOn: Binding(
                    get: { request.acknowledgedWarnings }, set: { offload.acknowledgeWarnings($0) }
                ))
            }
        }
    }

    @ViewBuilder
    private var drivePicker: some View {
        if volumes.driveCandidates.isEmpty {
            Text("Plug in an external drive").font(.system(size: 14, weight: .medium, design: .monospaced))
        } else {
            Menu {
                ForEach(volumes.driveCandidates) { volume in
                    Toggle(isOn: Binding(get: { volume.id == offload.driveVolumeID }, set: { _ in model.selectOffloadDrive(volume.id) })) {
                        Text("\(volume.name) · \(ByteSize.format(volume.availableBytes)) free")
                    }
                }
            } label: {
                Text(model.driveVolume.map { "\($0.name) · \(ByteSize.format($0.availableBytes)) free" } ?? "Choose a drive")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            .menuStyle(.button)
            .fixedSize()
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }

    @ViewBuilder
    private func footer(_ request: OffloadRequest) -> some View {
        HStack {
            Spacer()
            switch request.stage {
            case .checking, .review:
                Button("Cancel") { offload.dismissRequest() }.keyboardShortcut(.cancelAction)
                Button("Offload") { offload.confirmOffload(to: model.driveVolume) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm(request))
            case .running:
                Button("Stop") { offload.cancelOperation() }
            case .done, .failed:
                Button("Done") { offload.dismissRequest() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func canConfirm(_ request: OffloadRequest) -> Bool {
        guard let report = request.report, report.canOffload else { return false }
        return report.warnings.isEmpty || request.acknowledgedWarnings
    }
}
