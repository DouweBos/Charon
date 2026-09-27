// Stats/LowSpacePolicy.swift
// CharonKit
//
// Decides when free space is worth a notification. Levels only rise on crossing a threshold and only fall
// once space recovers past a margin, so a disk hovering at the line doesn't nag.

import Foundation

public struct LowSpacePolicy: Sendable, Hashable, Codable {
    public enum Level: Int, Sendable, Comparable, Codable {
        case normal, low, critical

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Warn when free space drops below this many bytes or this fraction of the disk, whichever is larger.
    public var lowBytes: Int64
    public var lowFraction: Double
    public var criticalBytes: Int64
    /// Space must recover this far past a threshold before its level clears.
    public var recoveryMargin: Int64

    public init(
        lowBytes: Int64 = 20_000_000_000, lowFraction: Double = 0.05,
        criticalBytes: Int64 = 5_000_000_000, recoveryMargin: Int64 = 2_000_000_000
    ) {
        self.lowBytes = lowBytes
        self.lowFraction = lowFraction
        self.criticalBytes = criticalBytes
        self.recoveryMargin = recoveryMargin
    }

    func lowThreshold(total: Int64) -> Int64 {
        max(lowBytes, Int64(Double(total) * lowFraction))
    }

    /// The level for `free` bytes, given the level we were at.
    public func level(free: Int64, total: Int64, previous: Level) -> Level {
        let low = lowThreshold(total: total)
        if free < criticalBytes { return .critical }
        if previous == .critical, free < criticalBytes + recoveryMargin { return .critical }
        if free < low { return .low }
        if previous >= .low, free < low + recoveryMargin { return .low }
        return .normal
    }
}
