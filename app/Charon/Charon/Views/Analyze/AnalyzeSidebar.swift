// Views/Analyze/AnalyzeSidebar.swift
// Charon

import CharonKit
import SwiftUI

struct AnalyzeSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(VolumesViewModel.self) private var volumes
    @State private var listHeight: CGFloat = .infinity

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            diskSummary
            ScrollView {
                LazyVStack(spacing: 6) {
                    if let peeked = model.peekedNode, let tree = model.currentScan?.tree {
                        PeekList(tree: tree, node: peeked, entries: model.entries(of: peeked),
                                 tint: Theme.treemapColor(navigator.peekColorIndex),
                                 groupedBelow: navigator.peekGroupedBelow, isLooseFiles: navigator.peekIsLooseFiles)
                    } else {
                        ForEach(model.levelEntries) { entry in
                            row(entry)
                        }
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
                                symbol: "externaldrive", tint: Theme.externalDrive, showsChevron: false
                            )
                            .onTapGesture { navigator.selectTab(.offload) }
                            .help("Moved to \(record.drive.name). Click to see it in Offload.")
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            // Hug the rows so the footer follows them, until they overflow and it sticks to the bottom.
            .frame(maxHeight: listHeight)
            .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { listHeight = max($1, 1) }
            if let volume = model.currentTarget?.isFolder == false ? model.currentVolume : nil {
                freeSpace(volume)
            }
            Spacer(minLength: 0)
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

    /// Like DaisyDisk's legend footer: what's free now, and what macOS can free on demand.
    private func freeSpace(_ volume: VolumeInfo) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack {
                Label("Free space", systemImage: "circle").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(ByteSize.format(max(volume.availableBytes - volume.purgeableBytes, 0))).font(.monoCaption)
            }
            HStack {
                Label("Free + purgeable", systemImage: "circle.dashed").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(ByteSize.format(volume.availableBytes)).font(.monoCaption)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, Theme.Spacing.md)
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
        .fileDrag { _ in
            guard entry.isNode else { return nil }
            return FileDragItem(
                path: entry.path, title: entry.title, size: entry.size,
                isDirectory: entry.isDirectory, tint: Theme.treemapColor(entry.colorIndex)
            )
        }
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
        if path == SystemIntegration.trashPath {
            Button("Empty Trash…", systemImage: "trash.slash") { model.requestEmptyTrash() }
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

/// What the rings are hovering: the folder's name and size, then its contents. Display only; moving the pointer
/// here ends the hover and the regular list comes back.
private struct PeekList: View {
    let tree: DiskTree
    let node: DiskTree.NodeID
    let entries: [LevelEntry]
    let tint: Color
    var groupedBelow: Int64?
    var isLooseFiles = false

    /// The entries this peek is about: a group shows only the small ones folded into it.
    private var candidates: [LevelEntry] {
        guard let groupedBelow else { return entries }
        return entries.filter { $0.size < groupedBelow && $0.kind != .unaccounted }
    }

    private var headerTitle: String {
        if isLooseFiles { return "Files" }
        if groupedBelow != nil { return "Smaller items" }
        return tree.name(node)
    }

    /// The folder a group belongs to, on its own line so the title doesn't get squeezed.
    private var headerSubtitle: String? {
        isLooseFiles || groupedBelow != nil ? "in \(tree.name(node))" : nil
    }

    private var headerSize: Int64 {
        if isLooseFiles { return tree.looseFilesSize(node) }
        if groupedBelow != nil { return candidates.reduce(0) { $0 + $1.size } }
        return tree.size(node)
    }

    /// Like DaisyDisk: list what matters (1% of the total or more, at most 12), fold the rest into one line.
    private var shown: [LevelEntry] {
        guard !isLooseFiles else { return [] }
        let total = max(headerSize, 1)
        return Array(candidates.filter { $0.size * 100 >= total && $0.kind != .others }.prefix(12))
    }

    private var smallerBytes: Int64 {
        guard !isLooseFiles else { return 0 }
        let shownIDs = Set(shown.map(\.id))
        return candidates.filter { !shownIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Circle().fill(tint).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(headerTitle).font(.system(size: 17, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    if let headerSubtitle {
                        Text(headerSubtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Text(ByteSize.format(headerSize)).font(.system(size: 17, weight: .medium, design: .rounded))
                    .layoutPriority(1)
            }
            .padding(.bottom, Theme.Spacing.xs)
            ForEach(shown) { entry in
                HStack(spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(entry.kind == .others || entry.kind == .looseFiles ? Theme.treemapNeutral : tint)
                        .frame(width: 7, height: 7)
                    Text(entry.title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(entry.isNode ? Theme.textPrimary : Theme.textSecondary)
                    Spacer()
                    Text(ByteSize.format(entry.size)).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            if smallerBytes > 0 {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(Theme.treemapNeutral).frame(width: 7, height: 7)
                    Text("Smaller items").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(ByteSize.format(smallerBytes)).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            if isLooseFiles {
                Text("Files too small to show individually, directly in this folder.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else if candidates.isEmpty {
                Text(tree.isDirectory(node) ? "Empty folder" : "File").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
