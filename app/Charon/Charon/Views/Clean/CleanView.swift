// Views/Clean/CleanView.swift
// Charon
//
// Known caches and leftovers with their sizes. Selected categories go to the Trash, or are deleted if Settings says so.

import CharonKit
import SwiftUI

struct CleanView: View {
    @Environment(CleanViewModel.self) private var clean
    @AppStorage(AppSettings.deletePermanently) private var deletePermanently = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            summary
            if let message = clean.message {
                Banner(symbol: "info.circle", message: message, onDismiss: { clean.dismissMessage() })
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(CleanCategory.Group.allCases, id: \.self) { group in
                        let rows = clean.rows(in: group)
                        if !rows.isEmpty {
                            Text(group.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(rows) { row in CleanRowView(row: row) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .onAppear { clean.measureIfNeeded() }
        .confirmationDialog(
            deletePermanently
                ? "Delete \(ByteSize.format(clean.selectedBytes)) of caches and leftovers permanently?"
                : "Move \(ByteSize.format(clean.selectedBytes)) of caches and leftovers to the Trash?",
            isPresented: Binding(get: { clean.isConfirming }, set: { if !$0 { clean.cancelClean() } })
        ) {
            Button(deletePermanently ? "Delete" : "Move to Trash", role: .destructive) { clean.confirmClean() }
            Button("Cancel", role: .cancel) { clean.cancelClean() }
        } message: {
            Text(clean.deletesSimulators
                ? "Selected simulators are deleted with simctl and can't be restored from the Trash. Apps rebuild caches as needed."
                : "Apps rebuild these as needed. Quit apps whose caches you're clearing for the best result.")
        }
    }

    private var summary: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label("Selected", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                Text(ByteSize.format(clean.selectedBytes)).font(.statValue)
            }
            Spacer()
            if clean.isMeasuring || clean.isCleaning {
                ProgressView().controlSize(.small)
            }
            Button("Rescan", systemImage: "arrow.clockwise") { clean.measure() }
                .disabled(clean.isMeasuring)
            Button(deletePermanently ? "Delete" : "Move to Trash") { clean.requestClean() }
                .buttonStyle(.borderedProminent)
                .disabled(clean.selectedBytes == 0 || clean.isCleaning)
        }
        .card()
    }
}

struct CleanRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(CleanViewModel.self) private var clean
    let row: CleanViewModel.Row
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                if row.category.mode == .emptyTrash {
                    Image(systemName: row.category.symbol).frame(width: 18)
                } else if row.category.picksItems {
                    Toggle(sources: itemBindings, isOn: \.self) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .disabled(!row.hasItems)
                        .accessibilityLabel(row.category.title)
                } else {
                    Toggle("", isOn: Binding(get: { clean.isSelected(row.id) }, set: { _ in clean.toggle(row.id) }))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel(row.category.title)
                }
                Image(systemName: row.category.symbol).foregroundStyle(Theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(row.category.title).font(.system(size: 14, weight: .medium))
                        safetyBadge
                    }
                    Text(row.category.detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.category.mode == .contents, let location = row.locations.first {
                        Text(row.locations.count == 1 ? LocationActions.display(location) : "\(row.locations.count) locations")
                            .font(.monoCaption).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                size
                if row.category.mode == .emptyTrash {
                    Button("Empty Trash…") { model.requestEmptyTrash() }.disabled(row.bytes == 0)
                }
                if let items = row.items, !items.isEmpty {
                    Button { isExpanded.toggle() } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isExpanded ? "Hide items" : "Show items")
                }
            }
            if isExpanded, let items = row.items {
                let limit = row.category.picksItems ? items.count : 25
                VStack(spacing: 2) {
                    ForEach(items.prefix(limit)) { item in
                        CleanItemRow(item: item, isPickable: row.category.picksItems)
                    }
                    if items.count > limit {
                        Text("and \(items.count - limit) more").font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.leading, row.category.picksItems ? 28 : 56)
            }
        }
        .card(padding: Theme.Spacing.md)
        .contextMenu {
            if !row.locations.isEmpty { LocationActions(locations: row.locations) }
        }
    }

    private var itemBindings: [Binding<Bool>] {
        (row.items ?? []).map { item in
            Binding(get: { clean.isItemSelected(item) }, set: { clean.setItem(item, selected: $0) })
        }
    }

    @ViewBuilder
    private var size: some View {
        if let error = row.error {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning).help(error)
        } else if row.items == nil {
            ProgressView().controlSize(.small)
        } else {
            Text(ByteSize.format(row.bytes)).font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(row.bytes > 0 ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    private var safetyBadge: StatusBadge {
        switch row.category.safety {
        case .regenerated: StatusBadge(title: "Rebuilt automatically", symbol: "arrow.triangle.2.circlepath", tone: .positive)
        case .review: StatusBadge(title: "Review first", symbol: "eye", tone: .caution)
        }
    }
}

private struct CleanItemRow: View {
    @Environment(CleanViewModel.self) private var clean
    let item: CleanItem
    let isPickable: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if isPickable {
                Toggle("", isOn: Binding(get: { clean.isItemSelected(item) }, set: { clean.setItem(item, selected: $0) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel(item.title ?? item.url.lastPathComponent)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let title = item.title {
                    Text(title).font(.system(size: 13)).lineLimit(1)
                } else {
                    Text(item.url.lastPathComponent).font(.monoCaption).lineLimit(1).truncationMode(.middle)
                }
                if let detail = item.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer()
            Text(ByteSize.format(item.bytes)).font(.monoCaption).foregroundStyle(Theme.textSecondary)
            Button { SystemIntegration.revealInFinder(item.url.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reveal in Finder")
        }
        .contentShape(Rectangle())
        .contextMenu { LocationActions(locations: [item.url]) }
    }
}
