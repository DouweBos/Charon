// Views/Analyze/LargestFilesView.swift
// Charon
//
// The biggest files under the drilled-into folder, as a sortable table.

import CharonKit
import SwiftUI

struct LargestFilesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @AppStorage(AppSettings.largeFileThresholdMB) private var thresholdMB = 50

    let tree: DiskTree
    let focus: DiskTree.NodeID

    struct Row: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var name: String
        var folder: String
        var size: Int64
    }

    @State private var rows: [Row] = []
    @State private var sortOrder = [KeyPathComparator(\Row.size, order: .reverse)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Table(rows, selection: Binding(get: { navigator.selectedPath }, set: { navigator.select($0) }), sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { row in
                    Label(row.name, systemImage: "doc").lineLimit(1)
                }
                TableColumn("Size", value: \.size) { row in
                    Text(ByteSize.format(row.size)).font(.monoCaption)
                }
                .width(min: 80, ideal: 100, max: 140)
                TableColumn("Folder", value: \.folder) { row in
                    Text(row.folder).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .contextMenu(forSelectionType: String.self) { paths in
                if let path = paths.first, let row = rows.first(where: { $0.path == path }) {
                    NodeActions(path: row.path, size: row.size, isDirectory: false, canOpen: false)
                }
            } primaryAction: { paths in
                guard let path = paths.first else { return }
                MainActor.assumeIsolated { SystemIntegration.revealInFinder(path) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .onChange(of: sortOrder) { rows.sort(using: sortOrder) }

            Text("Files of \(thresholdMB) MB and up. Smaller files are grouped into their folders.")
                .font(.monoCaption).foregroundStyle(Theme.textSecondary)
        }
        .task(id: TaskKey(nodes: tree.nodeCount, focus: focus, size: tree.size(focus))) {
            let tree = tree
            let focus = focus
            let computed = await Task.detached(priority: .userInitiated) {
                tree.largestFiles(under: focus, limit: 500).map { node in
                    let path = tree.displayPath(node)
                    return Row(path: path, name: tree.name(node), folder: (path as NSString).deletingLastPathComponent,
                               size: tree.size(node))
                }
            }.value
            rows = computed.sorted(using: sortOrder)
        }
    }

    private struct TaskKey: Hashable {
        var nodes: Int
        var focus: DiskTree.NodeID
        var size: Int64
    }
}
