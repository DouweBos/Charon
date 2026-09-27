// Views/Analyze/CollectorBar.swift
// Charon
//
// Strip under the treemap showing what's collected, with review and move-to-Trash.

import CharonKit
import SwiftUI

struct CollectorBar: View {
    @Environment(CollectorViewModel.self) private var collector
    @State private var isReviewing = false

    var body: some View {
        if !collector.isEmpty || collector.message != nil {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "tray.full").foregroundStyle(Theme.accent)
                if let message = collector.message {
                    Text(message).font(.system(size: 13)).lineLimit(2)
                    Spacer()
                    Button("OK") { collector.dismissMessage() }
                } else {
                    Text("Collector").font(.system(size: 13, weight: .semibold))
                    Text("\(collector.items.count) items · \(ByteSize.format(collector.totalBytes))")
                        .font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Review") { isReviewing = true }
                    Button("Clear") { collector.clear() }
                    Button("Move to Trash") { collector.requestTrash() }
                        .disabled(collector.isTrashing)
                }
            }
            .card(padding: Theme.Spacing.md)
            .popover(isPresented: $isReviewing, arrowEdge: .top) { CollectorReview() }
            .confirmationDialog(
                "Move \(collector.items.count) items (\(ByteSize.format(collector.totalBytes))) to the Trash?",
                isPresented: Binding(get: { collector.isConfirming }, set: { if !$0 { collector.cancelTrash() } })
            ) {
                Button("Move to Trash", role: .destructive) { collector.confirmTrash() }
                Button("Cancel", role: .cancel) { collector.cancelTrash() }
            } message: {
                Text("You can put them back from the Trash until it's emptied.")
            }
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
