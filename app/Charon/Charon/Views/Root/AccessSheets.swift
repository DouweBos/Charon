// Views/Root/AccessSheets.swift
// Charon
//
// Full Disk Access onboarding and the list of folders a scan couldn't read.

import AppKit
import CharonKit
import SwiftUI

struct FullDiskAccessSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                PlanetView().frame(width: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let Charon see the whole disk").font(.system(size: 18, weight: .semibold))
                    Text("Without Full Disk Access, Mail, Messages, Safari and other protected folders count as unknown space.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                step(1, "Open Privacy & Security → Full Disk Access.")
                step(2, "Turn on Charon. If it isn't listed, drag Charon from Finder into the list.")
                step(3, "Quit and reopen Charon when macOS asks.")
            }
            if model.hasFullDiskAccess {
                Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Show Charon in Finder") { SystemIntegration.revealInFinder(Bundle.main.bundlePath) }
                Spacer()
                Button("Not Now") { navigator.dismissSheet() }.keyboardShortcut(.cancelAction)
                Button("Open Settings") { SystemIntegration.openFullDiskAccessSettings() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 520, height: 330)
        .background(Theme.background)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckFullDiskAccess()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .background(Theme.subtleFill, in: Circle())
            Text(text).font(.system(size: 13))
        }
    }
}

struct RestrictedFoldersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    private var paths: [String] {
        (model.currentScan?.progress.unreadablePaths ?? []).map(FerryPreflight.userFacingPath).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Restricted folders").font(.system(size: 18, weight: .semibold))
            Text(summary).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            List(paths, id: \.self) { path in
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.textSecondary)
                    Text(path).font(.monoCaption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Reveal") { SystemIntegration.revealInFinder(path) }
                        .buttonStyle(.borderless)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
            HStack {
                Spacer()
                Button("Done") { navigator.dismissSheet() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 600, height: 460)
        .background(Theme.background)
    }

    private var summary: String {
        let total = model.currentScan?.progress.unreadableDirectories ?? 0
        let shown = paths.count < total ? " Showing the first \(paths.count)." : ""
        return "\(total.formatted()) folders are owned by macOS or other users, so Charon can't size them."
            + " Their space is part of System & other.\(shown)"
    }
}
