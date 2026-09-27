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
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var diskSummary: some View {
        Menu {
            Section("Disks") {
                ForEach(model.targets.filter { !$0.isFolder }) { target in
                    Button { navigator.selectTarget(target.id) } label: {
                        Label("\(target.name) (\(target.volume.map { ByteSize.capacity($0.totalBytes) } ?? "–"))",
                              systemImage: target.symbol)
                    }
                }
            }
            Section("Folders") {
                ForEach(model.targets.filter(\.isFolder)) { target in
                    Button { navigator.selectTarget(target.id) } label: {
                        Label(target.displayRoot, systemImage: target.symbol)
                    }
                }
                Button("Scan Folder…", systemImage: "folder.badge.plus") { model.chooseFolderToScan() }
            }
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                PlanetView().frame(width: 150)
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
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Choose a disk or folder")
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
