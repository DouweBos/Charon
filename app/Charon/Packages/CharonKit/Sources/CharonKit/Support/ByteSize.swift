// Support/ByteSize.swift
// CharonKit
//
// Decimal (1000-based) byte formatting, matching Finder's disk sizes.

import Foundation

public enum ByteSize {

    /// Formats bytes like "226.39 GB", "512 MB", "12 KB".
    public static func format(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(max(bytes, 0))
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        switch unit {
        case 0: return "\(Int(value)) \(units[0])"
        case 1, 2: return "\(Int(value.rounded())) \(units[unit])"
        default: return String(format: "%.2f %@", value, units[unit])
        }
    }

    /// Whole-unit capacity like "494 GB" or "2 TB", for disk totals.
    public static func capacity(_ bytes: Int64) -> String {
        let value = Double(max(bytes, 0))
        if value >= 1e12 { return String(format: value >= 1e13 ? "%.0f TB" : "%.1f TB", value / 1e12) }
        return String(format: "%.0f GB", value / 1e9)
    }

    /// Formats bytes-per-second like "1 KB/s".
    public static func formatRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1000 else { return "\(Int(max(bytesPerSecond, 0))) B/s" }
        return format(Int64(bytesPerSecond)) + "/s"
    }

    /// "72%" style share of a total, clamped to 0...100.
    public static func percent(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let value = min(max(Double(part) / Double(total) * 100, 0), 100)
        return value > 0 && value < 1 ? "<1%" : "\(Int(value.rounded()))%"
    }
}
