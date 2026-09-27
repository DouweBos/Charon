// Views/Uninstall/UninstallView.swift
// Charon
//
// App list on the left, the selected app and its leftovers on the right.

import AppKit
import CharonKit
import SwiftUI

struct UninstallView: View {
    @Environment(UninstallViewModel.self) private var uninstall

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.sm) {
                TextField("Search apps", text: Binding(get: { uninstall.query }, set: { uninstall.setQuery($0) }))
                    .textFieldStyle(.roundedBorder)
                List(uninstall.filteredApps, selection: Binding(get: { uninstall.selectedAppID }, set: { uninstall.select($0) })) { app in
                    AppRow(app: app).tag(app.id)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay { if uninstall.isLoading { ProgressView() } }
            }
            .frame(width: 340)

            if let app = uninstall.selectedApp {
                AppDetail(app: app)
            } else {
                ContentUnavailableView("Choose an app", systemImage: "app.dashed",
                                       description: Text("See how much space it and its leftovers take."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .onAppear { uninstall.loadIfNeeded() }
    }
}

private struct AppRow: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(lastUsed).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(ByteSize.format(app.bytes)).font(.monoCaption)
        }
        .padding(.vertical, 2)
    }

    private var lastUsed: String {
        guard let date = app.lastUsed else { return "Never opened" }
        return "Opened " + date.formatted(.relative(presentation: .named))
    }
}

private struct AppDetail: View {
    @Environment(UninstallViewModel.self) private var uninstall
    let app: InstalledApp

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 20, weight: .semibold))
                    Text([app.version.map { "Version \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                        .font(.monoCaption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteSize.format(uninstall.removalBytes)).font(.statValue)
                    Text("to remove").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .card()

            if let message = uninstall.message {
                Banner(symbol: "info.circle", message: message, onDismiss: { uninstall.dismissMessage() })
            }
            if uninstall.isSelectedAppRunning {
                Banner(symbol: "exclamationmark.triangle", message: "\(app.name) is running. Quit it before uninstalling.")
            }

            Text("Leftovers").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    if uninstall.isLoadingLeftovers {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if uninstall.leftovers.isEmpty {
                        Text("No leftovers found in your Library.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(uninstall.leftovers) { leftover in
                        leftoverRow(leftover)
                    }
                }
            }

            HStack {
                Button("Show in Finder") { SystemIntegration.revealInFinder(app.url.path) }
                Spacer()
                Button("Move to Trash") { uninstall.requestUninstall() }
                    .buttonStyle(.borderedProminent)
                    .disabled(uninstall.isSelectedAppRunning || uninstall.isUninstalling)
            }
        }
        .confirmationDialog(
            "Move \(app.name) and its selected leftovers (\(ByteSize.format(uninstall.removalBytes))) to the Trash?",
            isPresented: Binding(get: { uninstall.isConfirming }, set: { if !$0 { uninstall.cancelUninstall() } })
        ) {
            Button("Move to Trash", role: .destructive) { uninstall.confirmUninstall() }
            Button("Cancel", role: .cancel) { uninstall.cancelUninstall() }
        }
    }

    private func leftoverRow(_ leftover: AppLeftover) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Toggle("", isOn: Binding(get: { uninstall.isRemoving(leftover.id) }, set: { _ in uninstall.toggleLeftover(leftover.id) }))
                .toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel(leftover.url.lastPathComponent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(leftover.kind).font(.system(size: 13, weight: .medium))
                    if leftover.isUncertain {
                        StatusBadge(title: "Might belong to another app", symbol: "questionmark.circle", tone: .caution)
                    }
                }
                Text(leftover.url.path).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(ByteSize.format(leftover.bytes)).font(.monoCaption)
            Button { SystemIntegration.revealInFinder(leftover.url.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reveal in Finder")
        }
        .card(padding: Theme.Spacing.sm)
    }
}
