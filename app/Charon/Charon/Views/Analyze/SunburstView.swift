// Views/Analyze/SunburstView.swift
// Charon
//
// Rings view: each ring one level deeper, several levels at once. Layout comes from CharonKit.

import CharonKit
import SwiftUI

struct SunburstView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    let tree: DiskTree
    let focus: DiskTree.NodeID
    let unaccountedBytes: Int64

    @State private var hoveredID: Int?
    @State private var cache = LayoutCache<LayoutKey, [SunburstSegment]>()
    private let maxDepth = 6
    private let captionHeight: CGFloat = 16

    /// Everything the layout depends on; a new scan snapshot changes the node count or sizes.
    private struct LayoutKey: Hashable {
        var nodes: Int
        var focus: DiskTree.NodeID
        var size: Int64
        var unaccounted: Int64
    }

    private struct Geometry {
        var center: CGPoint
        var hole: CGFloat
        var ring: CGFloat

        func radii(_ depth: Int) -> (inner: CGFloat, outer: CGFloat) {
            (hole + CGFloat(depth - 1) * ring, hole + CGFloat(depth) * ring - 1)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let key = LayoutKey(nodes: tree.nodeCount, focus: focus, size: tree.size(focus), unaccounted: unaccountedBytes)
            let segments = cache.value(for: key) {
                SunburstLayout.segments(for: tree, focus: focus, maxDepth: maxDepth, unaccountedBytes: unaccountedBytes)
            }
            let area = CGSize(width: proxy.size.width, height: max(proxy.size.height - captionHeight - Theme.Spacing.xs, 0))
            let radius = max(min(area.width, area.height) / 2 - Theme.Spacing.sm, 10)
            let geometry = Geometry(
                center: CGPoint(x: area.width / 2, y: area.height / 2),
                hole: radius * 0.2, ring: radius * 0.8 / CGFloat(maxDepth)
            )
            let hovered = hoveredID.flatMap { id in segments.first { $0.id == id } }

            VStack(spacing: Theme.Spacing.xs) {
                ZStack {
                    // The rings don't depend on hover, so moving the pointer only redraws the highlight overlay.
                    Canvas { context, _ in
                        for segment in segments { draw(segment, geometry: geometry, in: &context) }
                    }
                    Canvas { context, _ in
                        for segment in segments where segment.id == hoveredID || isSelected(segment) {
                            context.stroke(path(segment, geometry: geometry), with: .color(Theme.textPrimary), lineWidth: 2)
                        }
                    }
                    .allowsHitTesting(false)
                    centerLabel(hovered: hovered)
                        .frame(width: geometry.hole * 1.8, height: geometry.hole * 1.8)
                        .position(geometry.center)
                        .allowsHitTesting(false)
                }
                .frame(width: area.width, height: area.height)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let id = hit(point, segments: segments, geometry: geometry)?.id
                        if id != hoveredID { hoveredID = id }
                    case .ended: hoveredID = nil
                    }
                }
                .onTapGesture { point in
                    if distance(point, geometry.center) < geometry.hole {
                        model.focusParent()
                    } else if let segment = hit(point, segments: segments, geometry: geometry) {
                        open(segment)
                    }
                }
                .contextMenu {
                    if let node = hovered?.node {
                        NodeActions(
                            path: tree.displayPath(node), size: tree.size(node),
                            isDirectory: tree.isDirectory(node), canOpen: !tree.children(node).isEmpty
                        )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rings of \(tree.displayPath(focus))")

                Text(caption(hovered))
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: captionHeight)
            }
        }
    }

    private func centerLabel(hovered: SunburstSegment?) -> some View {
        VStack(spacing: 2) {
            Text(ByteSize.format(hovered?.size ?? (tree.size(focus) + unaccountedBytes)))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(hovered?.title ?? tree.name(focus))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .minimumScaleFactor(0.6)
    }

    private func path(_ segment: SunburstSegment, geometry: Geometry) -> Path {
        let (inner, outer) = geometry.radii(segment.depth)
        let start = Angle.radians(segment.startAngle - .pi / 2)
        let end = Angle.radians(segment.endAngle - .pi / 2)
        var path = Path()
        path.addArc(center: geometry.center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: geometry.center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    private func draw(_ segment: SunburstSegment, geometry: Geometry, in context: inout GraphicsContext) {
        let path = path(segment, geometry: geometry)

        let isNeutral: Bool
        switch segment.content {
        case .unaccounted, .others: isNeutral = true
        default: isNeutral = false
        }
        context.fill(path, with: .color(Theme.sunburstFill(colorIndex: segment.colorIndex, depth: segment.depth, isNeutral: isNeutral)))
        context.stroke(path, with: .color(Theme.background), lineWidth: 1)
    }

    private func hit(_ point: CGPoint, segments: [SunburstSegment], geometry: Geometry) -> SunburstSegment? {
        let dx = point.x - geometry.center.x, dy = point.y - geometry.center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= geometry.hole else { return nil }
        let depth = Int((radius - geometry.hole) / geometry.ring) + 1
        guard depth <= maxDepth else { return nil }
        // Clockwise from 12 o'clock, in screen coordinates (y down).
        let angle = atan2(Double(dx), Double(-dy))
        return SunburstLayout.hitTest(segments, angle: angle, depth: depth)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        ((first.x - second.x) * (first.x - second.x) + (first.y - second.y) * (first.y - second.y)).squareRoot()
    }

    private func isSelected(_ segment: SunburstSegment) -> Bool {
        guard let node = segment.node else { return false }
        let path = tree.displayPath(node)
        return path == navigator.selectedPath || path == navigator.hoveredPath
    }

    private func open(_ segment: SunburstSegment) {
        switch segment.content {
        case .unaccounted:
            navigator.present(.hiddenSpace)
        case .others(let parent, _), .looseFiles(let parent):
            if parent != focus { navigator.focus(tree.displayPath(parent)) }
        case .node(let node):
            if segment.isDrillable { navigator.focus(tree.displayPath(node)) } else { navigator.select(tree.displayPath(node)) }
        }
    }

    private func caption(_ segment: SunburstSegment?) -> String {
        guard let segment else { return "Click a ring to open that folder. Click the center to go up." }
        switch segment.content {
        case .node(let node):
            return "\(tree.displayPath(node)) · \(ByteSize.format(segment.size))"
        case .looseFiles:
            return "Files directly in this folder · \(ByteSize.format(segment.size))"
        case .others(let parent, let count):
            return "\(count) smaller items in \(tree.name(parent)) · \(ByteSize.format(segment.size))"
        case .unaccounted:
            return "macOS, snapshots and space the scan can't see · \(ByteSize.format(segment.size)) · click for a breakdown"
        }
    }
}
