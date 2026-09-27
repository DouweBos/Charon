// Views/Stats/StatsRow.swift
// Charon

import CharonKit
import SwiftUI

struct StatsRow: View {
    @Environment(StatsViewModel.self) private var stats

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            let sample = stats.latest
            StatCard(
                title: "CPU", symbol: "cpu", color: Theme.statCPU,
                value: percent(sample?.cpuUsage), unit: "%",
                footnote: "Load: " + (sample.map { String(format: "%.2f", $0.loadAverage) } ?? "–"),
                history: stats.cpu, style: .bars
            )
            StatCard(
                title: "Memory", symbol: "memorychip", color: Theme.statMemory,
                value: percent(sample.map { ratio($0.memoryUsed, $0.memoryTotal) }), unit: "%",
                footnote: sample.map { "\(ByteSize.format($0.memoryUsed)) / \(ByteSize.format($0.memoryTotal))" } ?? "–",
                history: stats.memory
            )
            StatCard(
                title: "Disk", symbol: "internaldrive", color: Theme.statDisk,
                value: percent(sample.map { ratio($0.diskUsed, $0.diskTotal) }), unit: "%",
                footnote: sample.map { "\(ByteSize.format($0.diskTotal - $0.diskUsed)) free" } ?? "–",
                history: stats.disk
            )
            StatCard(
                title: "Battery", symbol: batterySymbol(sample?.battery), color: Theme.statBattery,
                value: sample?.battery.map { percent($0.level) } ?? "–", unit: sample?.battery == nil ? "" : "%",
                footnote: batteryFootnote(sample),
                history: stats.battery
            )
            StatCard(
                title: "Network", symbol: "network", color: Theme.statNetwork,
                value: sample.map { ByteSize.formatRate($0.networkInPerSecond + $0.networkOutPerSecond) } ?? "–",
                footnote: sample.map {
                    "↑ \(ByteSize.formatRate($0.networkOutPerSecond))  ↓ \(ByteSize.formatRate($0.networkInPerSecond))"
                } ?? "–",
                history: stats.network
            )
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func ratio(_ part: Int64, _ total: Int64) -> Double {
        total > 0 ? Double(part) / Double(total) : 0
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int((value * 100).rounded()))"
    }

    private func batterySymbol(_ battery: BatteryReading?) -> String {
        guard let battery else { return "powerplug" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.level {
        case 0.75...: return "battery.100percent"
        case 0.5..<0.75: return "battery.75percent"
        case 0.25..<0.5: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    private func batteryFootnote(_ sample: SystemSample?) -> String {
        guard let battery = sample?.battery else { return "No battery" }
        if battery.isCharging { return "Charging" }
        if battery.isOnPower { return "On power" }
        guard let minutes = battery.minutesRemaining else { return "Estimating…" }
        return String(format: "%.1f hrs left", Double(minutes) / 60)
    }
}
