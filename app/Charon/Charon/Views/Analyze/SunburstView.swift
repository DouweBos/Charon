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

    private struct RingsKey: Hashable {
        var layout: LayoutKey
        var width: CGFloat
        var height: CGFloat
    }

    private struct Geometry {
        var center: CGPoint
        var hole: CGFloat
        var rings: [(inner: Double, outer: Double)]

        func radii(_ depth: Int) -> (inner: CGFloat, outer: CGFloat) {
            let ring = rings[depth - 1]
            return (CGFloat(ring.inner), CGFloat(ring.outer) - 1)
        }

        func depth(at radius: CGFloat) -> Int? {
            rings.firstIndex { Double(radius) >= $0.inner && Double(radius) < $0.outer }.map { $0 + 1 }
        }
    }

    /// Room outside the last ring for the "more inside" rim.
    private let rimSpace: CGFloat = 7
    private let pulsePeriod: Double = 1.1

    var body: some View {
        GeometryReader { proxy in
            let key = LayoutKey(nodes: tree.nodeCount, focus: focus, size: tree.size(focus), unaccounted: unaccountedBytes)
            let segments = cache.value(for: key) {
                SunburstLayout.segments(for: tree, focus: focus, maxDepth: maxDepth, unaccountedBytes: unaccountedBytes)
            }
            let area = CGSize(width: proxy.size.width, height: max(proxy.size.height - captionHeight - Theme.Spacing.xs, 0))
            let radius = max(min(area.width, area.height) / 2 - Theme.Spacing.sm, 10)
            let hole = radius * 0.2
            let geometry = Geometry(
                center: CGPoint(x: area.width / 2, y: area.height / 2), hole: hole,
                rings: SunburstLayout.ringRadii(hole: Double(hole), outer: Double(radius - rimSpace), depth: maxDepth)
            )
            let hovered = hoveredID.flatMap { id in segments.first { $0.id == id } }

            VStack(spacing: Theme.Spacing.xs) {
                ZStack {
                    // The rings don't depend on hover, so moving the pointer only redraws the highlight overlay.
                    StaticCanvas(key: RingsKey(layout: key, width: area.width, height: area.height)) { context in
                        for segment in segments { draw(segment, geometry: geometry, in: &context) }
                    }
                    .equatable()
                    // Hovered segments breathe between full and half strength instead of getting an outline.
                    let highlighted = segments.filter { $0.id == hoveredID || isSelected($0) }
                    if !highlighted.isEmpty {
                        TimelineView(.animation) { timeline in
                            Canvas { context, _ in
                                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod
                                let fade = Theme.hoverPulseDepth * (1 - cos(phase * 2 * .pi)) / 2
                                for segment in highlighted {
                                    context.fill(path(segment, geometry: geometry), with: .color(Theme.background.opacity(fade)))
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    centerLabel(hovered: hovered)
                        // A square inscribed in the hole, so text never touches the ring.
                        .frame(width: geometry.hole * 1.4, height: geometry.hole * 1.4)
                        .position(geometry.center)
                        .allowsHitTesting(false)
                }
                .frame(width: area.width, height: area.height)
                .id(focus)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .contentShape(Rectangle())
                .fileDrag { point in
                    guard let target = hit(point, segments: segments, geometry: geometry), let node = target.node else { return nil }
                    return FileDragItem(
                        path: tree.realPath(node), title: target.title, size: target.size,
                        isDirectory: tree.isDirectory(node), tint: Theme.treemapColor(target.colorIndex)
                    )
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let segment = hit(point, segments: segments, geometry: geometry)
                        if segment?.id != hoveredID {
                            hoveredID = segment?.id
                            peek(segment)
                        }
                    case .ended:
                        hoveredID = nil
                        navigator.peek(nil)
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
                .onDisappear { navigator.peek(nil) }

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
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(hovered?.title ?? tree.name(focus))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
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
        if segment.hasHiddenChildren {
            // A thin band outside the last ring says there's more inside, like DaisyDisk.
            let outer = geometry.radii(segment.depth).outer
            var rim = Path()
            rim.addArc(center: geometry.center, radius: outer + 4, startAngle: .radians(segment.startAngle - .pi / 2),
                       endAngle: .radians(segment.endAngle - .pi / 2), clockwise: false)
            context.stroke(rim, with: .color(Theme.sunburstFill(colorIndex: segment.colorIndex, depth: segment.depth, isNeutral: false)),
                           lineWidth: 3)
        }
    }

    private func hit(_ point: CGPoint, segments: [SunburstSegment], geometry: Geometry) -> SunburstSegment? {
        let dx = point.x - geometry.center.x, dy = point.y - geometry.center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        guard let depth = geometry.depth(at: radius) else { return nil }
        // Clockwise from 12 o'clock, in screen coordinates (y down).
        let angle = atan2(Double(dx), Double(-dy))
        return SunburstLayout.hitTest(segments, angle: angle, depth: depth)
    }

    /// Shows the hovered segment's contents in the sidebar: a folder, the small items folded into a group,
    /// or the loose files of a folder.
    private func peek(_ segment: SunburstSegment?) {
        guard let segment else {
            navigator.peek(nil)
            return
        }
        switch segment.content {
        case .node(let node):
            navigator.peek(tree.displayPath(node), colorIndex: segment.colorIndex)
        case .others(let parent, _):
            navigator.peek(tree.displayPath(parent), colorIndex: segment.colorIndex, groupedBelow: segment.groupedBelow ?? .max)
        case .looseFiles(let parent):
            navigator.peek(tree.displayPath(parent), colorIndex: segment.colorIndex, looseFiles: true)
        case .unaccounted:
            navigator.peek(nil)
        }
    }

    /// Lets a hovered file or folder be dragged to the Collector, Finder or the Trash.
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
