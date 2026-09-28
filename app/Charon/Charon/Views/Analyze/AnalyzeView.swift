// Views/Analyze/AnalyzeView.swift
// Charon
//
// Sidebar with the disk and its biggest folders, the treemap, and live stats underneath.

import CharonKit
import QuickLook
import SwiftUI

struct AnalyzeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                AnalyzeSidebar()
                    .frame(width: 270)
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    AnalyzeHeader()
                    AnalyzeBanners()
                    TreemapPanel()
                    RestrictedNote()
                    CollectorBar()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .delete]) { press in
            handle(press.key)
        }
        .quickLookPreview(Binding(
            get: { navigator.previewPath.map { URL(fileURLWithPath: $0) } },
            set: { if $0 == nil { navigator.closePreview() } }
        ))
        .dropDestination(for: URL.self) { urls, _ in
            // A folder dragged out of this scan and released over it again isn't a request to scan it.
            guard let url = urls.first, !model.isInCurrentScan(url) else { return false }
            model.scanFolder(url)
            return true
        }
        .onAppear { model.startCurrentScan() }
        .onChange(of: navigator.targetID) { model.startCurrentScan() }
    }
}

extension AnalyzeView {
    /// Finder-like keys: arrows move and open, Space previews, Delete collects.
    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .upArrow: model.moveSelection(by: -1)
        case .downArrow: model.moveSelection(by: 1)
        case .rightArrow, .return: model.activateSelection()
        case .leftArrow: model.focusParent()
        case .space: model.previewSelection()
        case .delete: model.collectSelection()
        default: return .ignored
        }
        return .handled
    }
}

struct AnalyzeHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Breadcrumb(crumbs: crumbs) { crumb in
                    navigator.focus(crumb.id.isEmpty ? nil : crumb.id)
                }
                .layoutPriority(-1)
                Spacer(minLength: Theme.Spacing.lg)
                Picker("View", selection: Binding(get: { navigator.analyzeMode }, set: { navigator.setAnalyzeMode($0) })) {
                    ForEach(AnalyzeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .frame(height: 28)

            HStack(spacing: Theme.Spacing.md) {
                if let volume = model.currentVolume {
                    UsageBar(used: volume.usedBytes, total: volume.totalBytes, width: 180)
                }
                Spacer(minLength: Theme.Spacing.lg)
                if let scan = model.currentScan, !scan.isScanning, let scannedAt = scan.scannedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("Scanned \(scannedAt.formatted(.relative(presentation: .named)))")
                    }
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .help(scannedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Button { model.rescanCurrent() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Scan this disk again (⌘R)")
            }
        }
    }

    private var crumbs: [Breadcrumb.Crumb] {
        let rootTitle = model.currentTarget?.name ?? "Disk"
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
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        if !model.hasFullDiskAccess, !model.dismissedAccessBanner {
            Banner(
                symbol: "lock.shield",
                message: bannerMessage,
                actionTitle: "Grant Access",
                action: { navigator.present(.fullDiskAccess) },
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

/// Restricted folders are expected even with Full Disk Access, so this is a quiet note under the map, not a banner.
struct RestrictedNote: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        if model.hasFullDiskAccess || model.dismissedAccessBanner,
           let scan = model.currentScan, !scan.isScanning || scan.isAdministrator, scan.unreadableDirectories > 0 {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "lock")
                Text("\(scan.unreadableDirectories.formatted()) folders are restricted to macOS or other users;"
                     + " their space is in System & other.")
                    .lineLimit(1).truncationMode(.tail)
                if scan.isScanning {
                    Text("Scanning as administrator…")
                } else {
                    Button(scan.isAdministrator ? "Show" : "Scan as Administrator") {
                        if scan.isAdministrator { navigator.present(.restrictedFolders) } else { model.rescanCurrentAsAdministrator() }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
    }
}
