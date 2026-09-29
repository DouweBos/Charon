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
                VolumeRow(volume: boot, tint: bootTint)
            }
            ForEach(monitor.externals) { volume in
                VolumeRow(volume: volume, tint: .accentColor)
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

    private var bootTint: Color {
        switch monitor.level {
        case .normal: .accentColor
        case .low: MonitorTheme.warning
        case .critical: MonitorTheme.danger
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(volume.name).font(.headline).lineLimit(1)
                Spacer()
                Text("\(ByteSize.format(volume.availableBytes)) free").font(.system(.body, design: .monospaced))
            }
            ProgressView(value: usedFraction).tint(tint)
            Text("\(ByteSize.format(volume.usedBytes)) of \(ByteSize.format(volume.totalBytes)) used")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var usedFraction: Double {
        volume.totalBytes > 0 ? Double(volume.usedBytes) / Double(volume.totalBytes) : 0
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
