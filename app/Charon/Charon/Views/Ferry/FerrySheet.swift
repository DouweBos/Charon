// Views/Ferry/FerrySheet.swift
// Charon
//
// Confirm a ferry: preflight blockers and warnings, then progress, then the Obol.

import CharonKit
import SwiftUI

struct FerrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(FerryViewModel.self) private var ferry

    var body: some View {
        if let request = ferry.request {
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

    private func header(_ request: FerryRequest) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "ferry.fill").font(.system(size: 28)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ferry \(URL(fileURLWithPath: request.path).lastPathComponent)")
                    .font(.system(size: 18, weight: .semibold))
                Text(request.path).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func content(_ request: FerryRequest) -> some View {
        switch request.stage {
        case .checking:
            ProgressStrip(title: "Checking whether it's safe to ferry…", detail: "")
        case .review:
            if let report = request.report { review(report, request) }
        case .running:
            let progress = ferry.operation?.progress
            ProgressStrip(
                title: (progress?.stage.rawValue.capitalized ?? "Starting") + "…",
                detail: progress.map { "\(ByteSize.format($0.bytesDone)) of \(ByteSize.format($0.bytesTotal))" } ?? "",
                fraction: progress?.fraction,
                onCancel: { ferry.cancelOperation() }
            )
            Text("The original stays in place until every file on the Other Shore is verified.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        case .done(let reclaimed):
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("\(ByteSize.format(reclaimed)) reclaimed", systemImage: "centsign.circle.fill")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                let shoreName = model.shoreVolume?.name ?? "the Other Shore"
                Text("It now lives on \(shoreName). The symlink keeps every path working while the drive is connected.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        case .failed(let message):
            Banner(symbol: "xmark.octagon", message: message, tone: .negative)
        }
    }

    private func review(_ report: PreflightReport, _ request: FerryRequest) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xl) {
                fact("Size", ByteSize.format(report.bytes))
                fact("Other Shore", model.shoreVolume.map { "\($0.name) · \(ByteSize.format($0.availableBytes)) free" } ?? "None chosen")
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
            if report.canFerry, !report.warnings.isEmpty {
                Toggle("I understand the warnings", isOn: Binding(
                    get: { request.acknowledgedWarnings }, set: { ferry.acknowledgeWarnings($0) }
                ))
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }

    @ViewBuilder
    private func footer(_ request: FerryRequest) -> some View {
        HStack {
            Spacer()
            switch request.stage {
            case .checking, .review:
                Button("Cancel") { ferry.dismissRequest() }.keyboardShortcut(.cancelAction)
                Button("Ferry") { ferry.confirmFerry(to: model.shoreVolume) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm(request))
            case .running:
                Button("Stop") { ferry.cancelOperation() }
            case .done, .failed:
                Button("Done") { ferry.dismissRequest() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func canConfirm(_ request: FerryRequest) -> Bool {
        guard let report = request.report, report.canFerry else { return false }
        return report.warnings.isEmpty || request.acknowledgedWarnings
    }
}
