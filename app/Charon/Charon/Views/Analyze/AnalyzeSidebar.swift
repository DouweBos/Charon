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
            Button("Ferry to Other Shore…", systemImage: "ferry") {
                model.requestFerry(path: path, knownBytes: size)
            }
        }
    }
}
