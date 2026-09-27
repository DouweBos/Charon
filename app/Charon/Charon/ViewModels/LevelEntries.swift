// ViewModels/LevelEntries.swift
// Charon
//
// The items at the drilled-into level, in treemap order. Sidebar, keyboard and Quick Look share them.

import CharonKit
import Foundation

struct LevelEntry: Identifiable, Hashable {
    enum Kind: Hashable { case node(DiskTree.NodeID), looseFiles, others, unaccounted }

    var kind: Kind
    var path: String
    var title: String
    var size: Int64
    var isDirectory: Bool
    var drillable: Bool
    var colorIndex: Int

    var id: String { path }
    var isNode: Bool { if case .node = kind { true } else { false } }

    var symbol: String {
        switch kind {
        case .node: isDirectory ? "folder" : "doc"
        case .looseFiles: "doc.on.doc"
        case .others: "square.stack"
        case .unaccounted: "gearshape"
        }
    }
}

extension AppModel {
    var levelEntries: [LevelEntry] {
        guard let tree = currentScan?.tree else { return [] }
        let focus = focusNode
        let base = tree.displayPath(focus)
        let entries = TreemapLayout.entries(for: tree, parent: focus, unaccountedBytes: unaccountedBytes, limit: 60)
        return entries.enumerated().map { index, entry in
            switch entry.content {
            case .node(let node):
                return LevelEntry(kind: .node(node), path: tree.displayPath(node), title: entry.title, size: entry.size,
                                  isDirectory: tree.isDirectory(node), drillable: entry.nestable, colorIndex: index)
            case .looseFiles:
                return LevelEntry(kind: .looseFiles, path: base + "#files", title: entry.title, size: entry.size,
                                  isDirectory: false, drillable: false, colorIndex: index)
            case .others:
                return LevelEntry(kind: .others, path: base + "#others", title: entry.title, size: entry.size,
                                  isDirectory: false, drillable: false, colorIndex: index)
            case .unaccounted:
                return LevelEntry(kind: .unaccounted, path: "#unaccounted", title: entry.title, size: entry.size,
                                  isDirectory: false, drillable: false, colorIndex: index)
            }
        }
    }

    var selectedEntry: LevelEntry? {
        guard let selected = navigator.selectedPath else { return nil }
        return levelEntries.first { $0.path == selected }
    }

    /// Click / Return: drill into folders, explain hidden space, otherwise just select.
    func activate(_ entry: LevelEntry) {
        switch entry.kind {
        case .unaccounted: navigator.present(.hiddenSpace)
        case .node where entry.drillable: navigator.focus(entry.path)
        default: navigator.select(entry.path)
        }
    }

    func moveSelection(by offset: Int) {
        let entries = levelEntries
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.path == navigator.selectedPath }
        let next = current.map { min(max($0 + offset, 0), entries.count - 1) } ?? (offset > 0 ? 0 : entries.count - 1)
        navigator.select(entries[next].path)
    }

    func activateSelection() {
        if let entry = selectedEntry { activate(entry) }
    }

    func collectSelection() {
        guard let entry = selectedEntry, entry.isNode else { return }
        collect(path: entry.path, bytes: entry.size, isDirectory: entry.isDirectory)
    }

    func previewSelection() {
        guard let entry = selectedEntry, entry.isNode else { return }
        navigator.togglePreview(entry.path)
    }
}
