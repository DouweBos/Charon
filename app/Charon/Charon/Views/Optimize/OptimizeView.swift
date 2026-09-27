// Views/Optimize/OptimizeView.swift
// Charon
//
// What starts in the background, grouped by where it's installed.

import CharonKit
import ServiceManagement
import SwiftUI

struct OptimizeView: View {
    @Environment(OptimizeViewModel.self) private var optimize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Label("Background items", systemImage: "leaf").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    Text("\(optimize.items.count)").font(.statValue)
                    Text(optimize.orphanCount > 0 ? "\(optimize.orphanCount) point at apps that are gone" : "None left behind by removed apps")
                        .font(.monoCaption).foregroundStyle(optimize.orphanCount > 0 ? Theme.warning : Theme.textSecondary)
                }
                Spacer()
                if optimize.isLoading { ProgressView().controlSize(.small) }
                Button("Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
                Button("Reload", systemImage: "arrow.clockwise") { optimize.reload() }
            }
            .card()

            if let message = optimize.message {
                Banner(symbol: "info.circle", message: message, onDismiss: { optimize.dismissMessage() })
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                        let items = optimize.items(in: scope)
                        if !items.isEmpty {
                            Text(scope.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                                .padding(.top, Theme.Spacing.sm)
                            ForEach(items) { item in LaunchItemRow(item: item) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .onAppear { optimize.loadIfNeeded() }
        .confirmationDialog(
            "Remove \(optimize.pendingRemoval?.label ?? "")?",
            isPresented: Binding(get: { optimize.pendingRemoval != nil }, set: { if !$0 { optimize.cancelRemoval() } })
        ) {
            Button("Stop and Move to Trash", role: .destructive) { optimize.confirmRemoval() }
            Button("Cancel", role: .cancel) { optimize.cancelRemoval() }
        } message: {
            Text("It stops now and won't start at login. Restore the plist from the Trash to undo.")
        }
    }
}

private struct LaunchItemRow: View {
    @Environment(OptimizeViewModel.self) private var optimize
    let item: LaunchItem

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: item.scope == .systemDaemon ? "gearshape.2" : "person.crop.circle")
                .foregroundStyle(Theme.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(item.owningApp ?? item.label).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    badges
                }
                Text(item.program ?? item.label).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { SystemIntegration.revealInFinder(item.url.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reveal plist in Finder")
            if item.scope == .user {
                Button("Remove…") { optimize.requestRemoval(item) }
            }
        }
        .card(padding: Theme.Spacing.md)
    }

    @ViewBuilder
    private var badges: some View {
        if item.isOrphaned {
            StatusBadge(title: "App missing", symbol: "exclamationmark.triangle.fill", tone: .negative)
        }
        if item.isRunning {
            StatusBadge(title: "Running", symbol: "play.circle.fill", tone: .positive)
        }
        if item.runsAtLoad || item.keepsAlive {
            StatusBadge(title: item.keepsAlive ? "Always on" : "At login", symbol: "power", tone: .neutral)
        }
        if item.isDisabled {
            StatusBadge(title: "Disabled", symbol: "pause.circle", tone: .neutral)
        }
    }
}
