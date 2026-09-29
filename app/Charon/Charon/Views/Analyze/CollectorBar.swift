// Views/Analyze/CollectorBar.swift
// Charon
//
// Strip under the treemap showing what's collected, with review and removal.

import CharonKit
import SwiftUI

struct CollectorBar: View {
    @Environment(AppModel.self) private var model
    @Environment(CollectorViewModel.self) private var collector
    @State private var isReviewing = false
    @State private var isTargeted = false
    @AppStorage(AppSettings.deletePermanently) private var deletePermanently = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            switch collector.phase {
            case .countdown(let remaining):
                CountdownRing(remaining: remaining, total: CollectorViewModel.countdownSeconds)
                Text(deletePermanently
                    ? "Deleting \(collector.items.count) items (\(ByteSize.format(collector.totalBytes))) in \(remaining) s"
                    : "Moving \(collector.items.count) items (\(ByteSize.format(collector.totalBytes))) to the Trash in \(remaining) s")
                    .font(.system(size: 13)).monospacedDigit()
                Spacer()
                Button("Cancel") { collector.cancelRemoval() }
                    .keyboardShortcut(.cancelAction)
            case .removing(let done, let total, let permanently):
                ProgressStrip(
                    title: permanently ? "Deleting" : "Moving to the Trash",
                    detail: "\(ByteSize.format(done)) of \(ByteSize.format(total))",
                    fraction: total > 0 ? Double(done) / Double(total) : nil
                )
            case .idle:
                idle
            }
        }
        .card(padding: Theme.Spacing.md)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.accent, lineWidth: 2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.collectDropped(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
        .popover(isPresented: $isReviewing, arrowEdge: .top) { CollectorReview() }
    }

    @ViewBuilder
    private var idle: some View {
        Image(systemName: collector.isEmpty ? "tray" : "tray.full").foregroundStyle(Theme.accent)
        if collector.isEmpty, collector.message == nil {
            Text("Drag files and folders here to collect them")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
        } else if let message = collector.message {
            Text(message).font(.system(size: 13)).lineLimit(2)
            Spacer()
            if collector.canEmptyTrash {
                Button("Empty Trash…") { model.requestEmptyTrash() }
            }
            Button("OK") { collector.dismissMessage() }
        } else {
            Text("Collector").font(.system(size: 13, weight: .semibold))
            Text("\(collector.items.count) items · \(ByteSize.format(collector.totalBytes))")
                .font(.monoCaption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Review") { isReviewing = true }
            Button("Clear") { collector.clear() }
            Button(deletePermanently ? "Delete" : "Move to Trash") { collector.requestRemoval() }
        }
    }
}

struct CollectorReview: View {
    @Environment(CollectorViewModel.self) private var collector

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Collected").font(.system(size: 14, weight: .semibold))
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(collector.items) { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder" : "doc").foregroundStyle(Theme.accent)
                            Text(item.path).font(.monoCaption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(ByteSize.format(item.bytes)).font(.monoCaption)
                            Button { collector.remove(item.path) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove from Collector")
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 460, height: 300)
    }
}
