// DesignSystem/StatCard.swift
// Charon

import SwiftUI

struct StatCard: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String
    var unit: String = ""
    let footnote: String
    let history: [Double]
    var style: Sparkline.Style = .line

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.statValue)
                Text(unit).font(.statUnit)
            }
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Sparkline(values: history, color: color, style: style)
                .frame(height: 30)
            Text(footnote)
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        StatCard(title: "CPU", symbol: "cpu", color: Theme.statCPU, value: "14", unit: "%", footnote: "Load: 1.46",
                 history: [0.1, 0.2, 0.4, 0.3, 0.15, 0.2], style: .bars)
        StatCard(title: "Battery", symbol: "battery.75percent", color: Theme.statBattery, value: "72", unit: "%",
                 footnote: "4.1 hrs left", history: [0.74, 0.73, 0.72])
        StatCard(title: "Network", symbol: "network", color: Theme.statNetwork, value: "1 KB/s", footnote: "↑ 1 KB/s  ↓ 1 KB/s",
                 history: [])
    }
    .padding()
    .frame(width: 700)
    .background(Theme.background)
}
