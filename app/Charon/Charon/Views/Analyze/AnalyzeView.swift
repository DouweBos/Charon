// Views/Analyze/AnalyzeView.swift
// Charon
//
// Sidebar with the disk and its biggest folders, the treemap, and live stats underneath.

import CharonKit
import SwiftUI

struct AnalyzeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @AppStorage(AppSettings.showStats) private var showStats = true

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                AnalyzeSidebar()
                    .frame(width: 270)
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    AnalyzeHeader()
                    AnalyzeBanners()
                    TreemapPanel()
                }
            }
            if showStats {
                StatsRow()
                    .frame(height: 150)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .onAppear { model.startCurrentScan() }
        .onChange(of: navigator.volumeID) { model.startCurrentScan() }
    }
}

struct AnalyzeHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 2) {
                Button { navigator.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!navigator.canGoBack)
                    .accessibilityLabel("Back")
                Button { navigator.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!navigator.canGoForward)
                    .accessibilityLabel("Forward")
            }
            .buttonStyle(.borderless)
            Breadcrumb(crumbs: crumbs) { crumb in
                navigator.focus(crumb.id.isEmpty ? nil : crumb.id)
            }
            Spacer()
            if let scan = model.currentScan, !scan.isScanning, let scannedAt = scan.scannedAt {
                Text("Scanned \(Text(scannedAt, style: .relative)) ago")
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .help(scannedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let volume = model.currentVolume {
                UsageBar(used: volume.usedBytes, total: volume.totalBytes)
            }
            Button { model.rescanCurrent() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Rescan")
                .accessibilityLabel("Rescan")
        }
        .frame(height: 28)
    }

    private var crumbs: [Breadcrumb.Crumb] {
        let rootTitle = model.currentVolume?.name ?? "Disk"
        guard let tree = model.currentScan?.tree else { return [.init(id: "", title: rootTitle)] }
        return tree.lineage(model.focusNode).map { node in
            node == DiskTree.root
                ? .init(id: "", title: rootTitle)
                : .init(id: tree.displayPath(node), title: tree.name(node))
        }
    }
}

struct AnalyzeBanners: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.hasFullDiskAccess, !model.dismissedAccessBanner {
            Banner(
                symbol: "lock.shield",
                message: bannerMessage,
                actionTitle: "Open Settings",
                action: { SystemIntegration.openFullDiskAccessSettings() },
                onDismiss: { model.dismissAccessBanner() }
            )
        }
        if case .failed(let message) = model.currentScan?.phase {
            Banner(symbol: "xmark.octagon", message: "Scan failed: \(message)", tone: .negative)
        }
    }

    private var bannerMessage: String {
        let unreadable = model.currentScan?.progress.unreadableDirectories ?? 0
        let base = "Grant Charon Full Disk Access to see everything, then relaunch it."
        return unreadable > 0 ? "\(unreadable.formatted()) folders couldn't be read. " + base : base
    }
}
