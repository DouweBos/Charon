// Views/Analyze/ChangesView.swift
// Charon
//
// Where the space went since the previous scan of this disk or folder.

import CharonKit
import SwiftUI

struct ChangesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        if let comparison = model.currentComparison {
            content(comparison)
        } else {
            ContentUnavailableView(
                "No earlier scan yet", systemImage: "clock.arrow.circlepath",
                description: Text("Rescan later and Charon shows which folders grew since this scan.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private func content(_ comparison: ScanComparison) -> some View {
        let items = comparison.topGrowth()
        let total = comparison.current.size(DiskTree.root) - comparison.previous.size(DiskTree.root)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Since \(comparison.previousDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(total >= 0 ? "+" : "−")\(ByteSize.format(abs(total))) overall")
                    .font(.monoCaption)
                    .foregroundStyle(total > 0 ? Theme.warning : Theme.success)
            }
            if items.isEmpty {
                Text("No folder grew by 100 MB or more.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(items) { item in row(item) }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func row(_ item: GrowthItem) -> some View {
        Button {
            navigator.focus(item.path, mode: .map)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "arrow.up.right").foregroundStyle(Theme.warning).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text((item.path as NSString).lastPathComponent).font(.system(size: 14, weight: .medium))
                        if item.isNew { StatusBadge(title: "New", symbol: "sparkle", tone: .neutral) }
                    }
                    Text(item.path).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+\(ByteSize.format(item.delta))").font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.warning)
                    Text("now \(ByteSize.format(item.bytes))").font(.monoCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.sm)
    }
}
