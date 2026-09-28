// MonitorViews.swift
// CharonMonitor

import CharonKit
import SwiftUI

struct MonitorLabel: View {
    @Environment(MonitorModel.self) private var monitor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if monitor.showsFreeSpace, let boot = monitor.boot {
                Text(ByteSize.capacity(boot.availableBytes))
            }
        }
    }

    private var symbol: String {
        switch monitor.level {
        case .normal: monitor.disconnectedDrives.isEmpty ? "internaldrive" : "externaldrive.badge.exclamationmark"
        case .low: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

struct MonitorMenu: View {
    @Environment(MonitorModel.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let boot = monitor.boot {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(boot.name).font(.headline)
                        Spacer()
                        Text("\(ByteSize.format(boot.availableBytes)) free").font(.system(.body, design: .monospaced))
                    }
                    ProgressView(value: monitor.usedFraction)
                        .tint(monitor.level == .normal ? .accentColor : (monitor.level == .low ? MonitorTheme.warning : MonitorTheme.danger))
                    Text("\(ByteSize.format(boot.usedBytes)) of \(ByteSize.format(boot.totalBytes)) used")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if monitor.offloadCount > 0 {
                Divider()
                if monitor.disconnectedDrives.isEmpty {
                    Label("\(monitor.offloadCount) offloaded folders available", systemImage: "checkmark.circle")
                } else {
                    Label("\(monitor.disconnectedDrives.joined(separator: ", ")) disconnected", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(MonitorTheme.warning)
                }
            }
            if !monitor.growth.isEmpty, let since = monitor.growthSince {
                Divider()
                Text("Grew since \(since.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(monitor.growth) { item in
                        GrowthRow(item: item)
                    }
                }
                .padding(.horizontal, -6)
            }
            Divider()
            HStack {
                Button("Open Charon") { monitor.openCharon() }
                Spacer()
                Button("Refresh") { monitor.refresh(notify: false) }
                Button("Quit") { monitor.quit() }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// Opens the folder in Charon, where its contents show and it can be collected for the Trash.
private struct GrowthRow: View {
    @Environment(MonitorModel.self) private var monitor
    let item: GrowthItem
    @State private var isHovered = false

    var body: some View {
        Button { monitor.show(item.path) } label: {
            HStack {
                Text((item.path as NSString).lastPathComponent).lineLimit(1)
                Spacer()
                Text("+\(ByteSize.format(item.delta))").font(.system(.body, design: .monospaced))
                    .foregroundStyle(MonitorTheme.warning)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(isHovered ? MonitorTheme.rowHover : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Show \(item.path) in Charon")
        .contextMenu {
            Button("Show in Charon") { monitor.show(item.path) }
            Button("Show in Finder") { monitor.revealInFinder(item.path) }
        }
    }
}
