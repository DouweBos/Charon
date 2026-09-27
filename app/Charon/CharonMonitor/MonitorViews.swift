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
                ForEach(monitor.growth) { item in
                    HStack {
                        Text((item.path as NSString).lastPathComponent).lineLimit(1)
                        Spacer()
                        Text("+\(ByteSize.format(item.delta))").font(.system(.body, design: .monospaced))
                            .foregroundStyle(MonitorTheme.warning)
                    }
                    .help(item.path)
                }
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
