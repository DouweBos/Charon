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
                    ForEach(entries, id: \.path) { entry in
                        row(entry)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var diskSummary: some View {
        Menu {
            ForEach(volumes.volumes) { volume in
                Button {
                    navigator.selectVolume(volume.id)
                } label: {
                    Label("\(volume.name) (\(ByteSize.capacity(volume.totalBytes)))",
                          systemImage: volume.isBoot ? "internaldrive" : "externaldrive")
                }
            }
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                PlanetView().frame(width: 150)
                Text(model.currentVolume.map { ByteSize.capacity($0.totalBytes) } ?? "–")
                    .font(.capacityTitle)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(model.currentVolume.map { "\(ByteSize.format($0.usedBytes)) used" } ?? "")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
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
        .help("Choose a disk")
    }

    private struct Entry {
        var path: String
        var node: DiskTree.NodeID?
        var title: String
        var size: Int64
        var symbol: String
        var isDirectory: Bool
        var drillable: Bool
        var colorIndex: Int
        var isNeutral: Bool
    }

    private var entries: [Entry] {
        guard let tree = model.currentScan?.tree else { return [] }
        let focus = model.focusNode
        let base = tree.displayPath(focus)
        let levelEntries = TreemapLayout.entries(for: tree, parent: focus, unaccountedBytes: model.unaccountedBytes, limit: 60)
        return levelEntries.enumerated().map { index, entry in
            switch entry.content {
            case .node(let node):
                let isDirectory = tree.isDirectory(node)
                return Entry(path: tree.displayPath(node), node: node, title: entry.title, size: entry.size,
                             symbol: isDirectory ? "folder" : "doc", isDirectory: isDirectory,
                             drillable: entry.nestable, colorIndex: index, isNeutral: false)
            case .looseFiles:
                return Entry(path: base + "#files", title: entry.title, size: entry.size, symbol: "doc.on.doc",
                             isDirectory: false, drillable: false, colorIndex: index, isNeutral: false)
            case .others:
                return Entry(path: base + "#others", title: entry.title, size: entry.size, symbol: "square.stack",
                             isDirectory: false, drillable: false, colorIndex: index, isNeutral: false)
            case .unaccounted:
                return Entry(path: "#unaccounted", title: entry.title, size: entry.size, symbol: "gearshape",
                             isDirectory: false, drillable: false, colorIndex: index, isNeutral: true)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        let focusSize = model.currentScan?.tree.map { $0.size(model.focusNode) } ?? 0
        let total = max(focusSize + model.unaccountedBytes, 1)
        DirectoryRow(
            name: entry.title,
            detail: "\(ByteSize.format(entry.size)) · \(ByteSize.percent(entry.size, of: total))",
            symbol: entry.symbol,
            tint: entry.isNeutral ? Theme.treemapNeutral : Theme.treemapColor(entry.colorIndex),
            isSelected: navigator.selectedPath == entry.path,
            showsChevron: entry.drillable || entry.isNeutral
        )
        .onTapGesture {
            if entry.isNeutral {
                navigator.present(.hiddenSpace)
            } else if entry.drillable {
                navigator.focus(entry.path)
            } else {
                navigator.select(entry.path)
            }
        }
        .onHover { hovering in navigator.select(hovering ? entry.path : nil) }
        .contextMenu {
            if entry.node != nil {
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
        Button("Reveal in Finder", systemImage: "folder") { SystemIntegration.revealInFinder(path) }
        Button("Copy Path", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
        if isDirectory {
            Divider()
            Button("Ferry to Other Shore…", systemImage: "ferry") {
                model.requestFerry(path: path, knownBytes: size)
            }
        }
    }
}
