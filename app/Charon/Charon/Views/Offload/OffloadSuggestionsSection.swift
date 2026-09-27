// Views/Offload/OffloadSuggestionsSection.swift
// Charon
//
// The biggest folders in your home that are safe to move, from the last startup disk scan.

import CharonKit
import SwiftUI

struct OffloadSuggestionsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggestions = model.offloadSuggestions
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Suggestions").font(.system(size: 15, weight: .semibold)).padding(.top, Theme.Spacing.md)
            if suggestions.isEmpty {
                Text(model.hasBootScan
                     ? "No folders of 1 GB or more in your home folder can be moved safely."
                     : "Scan the startup disk in Analyze to get suggestions.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            ForEach(suggestions) { suggestion in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "folder").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((suggestion.path as NSString).lastPathComponent).font(.system(size: 14, weight: .medium))
                        Text(suggestion.path).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if let modified = suggestion.lastModified {
                        Text("Changed \(modified.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    Text(ByteSize.format(suggestion.bytes)).font(.system(size: 14, weight: .medium, design: .monospaced))
                    Button("Move…") { model.requestOffload(path: suggestion.path, knownBytes: suggestion.bytes) }
                }
                .card(padding: Theme.Spacing.md)
            }
        }
    }
}
