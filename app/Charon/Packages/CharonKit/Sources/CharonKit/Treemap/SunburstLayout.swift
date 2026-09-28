// Treemap/SunburstLayout.swift
// CharonKit
//
// Concentric rings: each ring is one level deeper, each segment's angle is its share of the focus.
// Angles are radians measured clockwise from 12 o'clock.

import Foundation

public struct SunburstSegment: Sendable, Hashable, Identifiable {
    public var id: Int
    public var content: TreemapTile.Content
    public var title: String
    public var size: Int64
    /// 1 is the innermost ring.
    public var depth: Int
    public var startAngle: Double
    public var endAngle: Double
    /// Index of the ring-1 ancestor, so a branch keeps one hue.
    public var colorIndex: Int
    public var isDrillable: Bool
    /// A folder on the outermost ring whose contents aren't drawn; the view marks its rim.
    public var hasHiddenChildren: Bool

    public var node: DiskTree.NodeID? {
        if case .node(let id) = content { return id }
        return nil
    }
}

public enum SunburstLayout {

    /// Inner and outer radius of each ring. Rings get thinner outward, as each level holds less.
    public static func ringRadii(hole: Double, outer: Double, depth: Int) -> [(inner: Double, outer: Double)] {
        let weights = (0..<depth).map { 1 / (1 + 0.22 * Double($0)) }
        let scale = (outer - hole) / weights.reduce(0, +)
        var radius = hole
        return weights.map { weight in
            defer { radius += weight * scale }
            return (radius, radius + weight * scale)
        }
    }

    /// Segments narrower than `minimumAngle` fold into one "smaller items" segment per parent.
    public static func segments(
        for tree: DiskTree, focus: DiskTree.NodeID, maxDepth: Int = 6,
        minimumAngle: Double = 0.012, unaccountedBytes: Int64 = 0
    ) -> [SunburstSegment] {
        var segments: [SunburstSegment] = []
        ring(
            tree: tree, parent: focus, depth: 1, start: 0, end: 2 * .pi, colorIndex: nil,
            maxDepth: maxDepth, minimumAngle: minimumAngle, unaccounted: unaccountedBytes, into: &segments
        )
        return segments
    }

    /// The segment at `angle` (clockwise from 12 o'clock) in ring `depth`.
    public static func hitTest(_ segments: [SunburstSegment], angle: Double, depth: Int) -> SunburstSegment? {
        let normalized = angle.truncatingRemainder(dividingBy: 2 * .pi)
        let positive = normalized < 0 ? normalized + 2 * .pi : normalized
        return segments.first { $0.depth == depth && positive >= $0.startAngle && positive < $0.endAngle }
    }

    // swiftlint:disable:next function_parameter_count
    private static func ring(
        tree: DiskTree, parent: DiskTree.NodeID, depth: Int, start: Double, end: Double, colorIndex: Int?,
        maxDepth: Int, minimumAngle: Double, unaccounted: Int64, into segments: inout [SunburstSegment]
    ) {
        let entries = TreemapLayout.entries(for: tree, parent: parent, unaccountedBytes: unaccounted, limit: 400)
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0, end > start else { return }
        let span = end - start

        var angle = start
        var smallBytes: Int64 = 0
        var smallCount = 0
        for (index, entry) in entries.enumerated() {
            let width = span * Double(entry.size) / Double(total)
            guard width >= minimumAngle else {
                smallBytes += entry.size
                if case .others(_, let count) = entry.content { smallCount += count } else { smallCount += 1 }
                continue
            }
            let color = colorIndex ?? index
            let drillable = entry.nestable
            segments.append(SunburstSegment(
                id: segments.count, content: entry.content, title: entry.title, size: entry.size, depth: depth,
                startAngle: angle, endAngle: angle + width, colorIndex: color, isDrillable: drillable,
                hasHiddenChildren: drillable && depth == maxDepth
            ))
            if drillable, depth < maxDepth, case .node(let target) = entry.content {
                ring(
                    tree: tree, parent: target, depth: depth + 1, start: angle, end: angle + width,
                    // A wedge wider than 40% of the circle lets its children pick fresh colors;
                    // otherwise a dominant folder (Users → your home) paints most of the chart one hue.
                    colorIndex: width > 0.4 * 2 * .pi ? nil : color,
                    maxDepth: maxDepth, minimumAngle: minimumAngle, unaccounted: 0, into: &segments
                )
            }
            angle += width
        }
        if smallBytes > 0 {
            segments.append(SunburstSegment(
                id: segments.count, content: .others(parent: parent, count: smallCount), title: "Smaller items",
                size: smallBytes, depth: depth, startAngle: angle, endAngle: end, colorIndex: colorIndex ?? entries.count,
                isDrillable: false, hasHiddenChildren: false
            ))
        }
    }
}
