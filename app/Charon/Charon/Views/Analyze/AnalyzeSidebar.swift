// Views/Analyze/AnalyzeSidebar.swift
// Charon

import CharonKit
import SwiftUI

struct AnalyzeSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(VolumesViewModel.self) private var volumes

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            diskSummary
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.levelEntries) { entry in
                        row(entry)
                    }
                    let offloaded = model.offloadedHere
                    if !offloaded.isEmpty {
                        Text("On external drives").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Theme.Spacing.sm)
                        ForEach(offloaded) { record in
                            DirectoryRow(
                                name: record.name,
                                detail: "\(ByteSize.format(record.bytes)) · on \(record.drive.name)",
                                symbol: "externaldrive", tint: Theme.statDisk, showsChevron: false
                            )
                            .onTapGesture { navigator.selectTab(.offload) }
                            .help("Moved to \(record.drive.name). Click to see it in Offload.")
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var diskSummary: some View {
        Button(action: showTargetMenu) {
            VStack(spacing: Theme.Spacing.sm) {
                CharonMark().frame(width: 120)
                Text(title).font(.capacityTitle).lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(subtitle)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose a disk or folder")
    }

    private func showTargetMenu() {
        let current = model.currentTarget?.id
        let disks = model.targets.filter { !$0.isFolder }.map { target in
            PopUpMenu.Item(
                title: target.volume.map { "\(target.name) · \(ByteSize.capacity($0.totalBytes))" } ?? target.name,
                symbol: target.symbol, isChecked: target.id == current
            ) { navigator.selectTarget(target.id) }
        }
        var folders = model.targets.filter(\.isFolder).map { target in
            PopUpMenu.Item(title: target.displayRoot, symbol: target.symbol, isChecked: target.id == current) {
                navigator.selectTarget(target.id)
            }
        }
        folders.append(PopUpMenu.Item(title: "Scan Folder…", symbol: "folder.badge.plus") { model.chooseFolderToScan() })
        PopUpMenu.show([PopUpMenu.Section(title: "Disks", items: disks), PopUpMenu.Section(title: "Folders", items: folders)])
    }

    private var title: String {
        guard let target = model.currentTarget else { return "–" }
        if target.isFolder {
            return ByteSize.format(model.currentScan?.tree?.size(DiskTree.root) ?? 0)
        }
        return target.volume.map { ByteSize.capacity($0.totalBytes) } ?? "–"
    }

    private var subtitle: String {
        guard let target = model.currentTarget else { return "" }
        if target.isFolder { return target.name }
        return target.volume.map { "\(ByteSize.format($0.usedBytes)) used" } ?? ""
    }

    @ViewBuilder
    private func row(_ entry: LevelEntry) -> some View {
        let focusSize = model.currentScan?.tree.map { $0.size(model.focusNode) } ?? 0
        let total = max(focusSize + model.unaccountedBytes, 1)
        DirectoryRow(
            name: entry.title,
            detail: "\(ByteSize.format(entry.size)) · \(ByteSize.percent(entry.size, of: total))",
            symbol: entry.symbol,
            tint: entry.kind == .unaccounted ? Theme.treemapNeutral : Theme.treemapColor(entry.colorIndex),
            isSelected: navigator.selectedPath == entry.path,
            showsChevron: entry.drillable || entry.kind == .unaccounted
        )
        .onTapGesture { model.activate(entry) }
        .onHover { hovering in navigator.hover(hovering ? entry.path : nil) }
        .contextMenu {
            if entry.isNode {
                NodeActions(path: entry.path, size: entry.size, isDirectory: entry.isDirectory, canOpen: entry.drillable)
            }
        }
    }
}

/// Actions shared by sidebar rows and treemap tiles.
struct NodeActions: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let path: String
    let size: Int64
    let isDirectory: Bool
    let canOpen: Bool

    var body: some View {
        if canOpen {
            Button("Open", systemImage: "arrow.down.right.and.arrow.up.left") { navigator.focus(path) }
        }
        Button("Quick Look", systemImage: "eye") { navigator.togglePreview(path) }
        Button("Reveal in Finder", systemImage: "folder") { SystemIntegration.revealInFinder(path) }
        if isDirectory {
            Button("Rescan This Folder", systemImage: "arrow.clockwise") { model.rescanFolder(path) }
            Button("Skip in Future Scans", systemImage: "eye.slash") { model.exclude(path) }
        }
        Button("Copy Path", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
        Divider()
        Button("Add to Collector", systemImage: "tray.and.arrow.down") {
            model.collect(path: path, bytes: size, isDirectory: isDirectory)
        }
        if isDirectory {
            Button("Move to External Drive…", systemImage: "externaldrive.badge.plus") {
                model.requestOffload(path: path, knownBytes: size)
            }
        }
    }
}
