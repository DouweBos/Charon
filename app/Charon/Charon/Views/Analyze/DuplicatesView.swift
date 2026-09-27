// Views/Analyze/DuplicatesView.swift
// Charon
//
// Identical large files in the current scan. Extra copies can be sent to the Collector.

import CharonKit
import SwiftUI

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @Environment(DuplicatesViewModel.self) private var duplicates

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                if duplicates.searchedTargetID == model.currentTarget?.id, !duplicates.isSearching {
                    Text("\(duplicates.groups.count) sets · \(ByteSize.format(duplicates.reclaimable)) in extra copies")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("Files of 50 MB and up with identical contents. APFS clones are left out.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let progress = duplicates.progress {
                    ProgressView(value: progress).frame(width: 120)
                    Button("Stop") { duplicates.cancel() }
                } else {
                    Button("Find Duplicates") {
                        if let tree = model.currentScan?.tree, let id = model.currentTarget?.id {
                            duplicates.search(tree: tree, targetID: id)
                        }
                    }
                    .disabled(model.currentScan?.phase != .complete)
                }
            }
            if let message = duplicates.errorMessage {
                Banner(symbol: "xmark.octagon", message: message, tone: .negative)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(duplicates.groups) { group in groupView(group) }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func groupView(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("\(group.paths.count) copies of \((group.paths[0] as NSString).lastPathComponent)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(ByteSize.format(group.bytes)) each").font(.monoCaption).foregroundStyle(Theme.textSecondary)
                Button("Collect Extra Copies") {
                    for path in group.paths.dropFirst() {
                        model.collect(path: OffloadPreflight.userFacingPath(path), bytes: group.bytes, isDirectory: false)
                    }
                }
                .help("Keeps the first copy and adds the rest to the Collector")
            }
            ForEach(Array(group.paths.enumerated()), id: \.element) { index, path in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: index == 0 ? "checkmark.circle" : "doc.on.doc")
                        .foregroundStyle(index == 0 ? Theme.success : Theme.textSecondary)
                    Text(OffloadPreflight.userFacingPath(path)).font(.monoCaption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { SystemIntegration.revealInFinder(path) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless).accessibilityLabel("Reveal in Finder")
                    Button { model.collect(path: OffloadPreflight.userFacingPath(path), bytes: group.bytes, isDirectory: false) } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderless).accessibilityLabel("Add to Collector")
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    }
}
