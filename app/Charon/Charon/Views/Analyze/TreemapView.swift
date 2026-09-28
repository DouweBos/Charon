// Views/Analyze/TreemapView.swift
// Charon
//
// Canvas-rendered treemap. Layout comes from CharonKit; this view only draws, hit-tests and routes clicks.

import CharonKit
import SwiftUI

private extension CGSize {
    static let unbounded = CGSize(width: 10_000, height: 1_000)
}

struct TreemapPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @AppStorage(AppSettings.treemapDepth) private var depth = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if !model.analyze.refreshingPaths.isEmpty {
                ProgressStrip(
                    title: "Rescanning \(model.analyze.refreshingPaths.map { ($0 as NSString).lastPathComponent }.sorted().joined(separator: ", "))",
                    detail: ""
                )
            }
            if let scan = model.currentScan, scan.isScanning {
                ProgressStrip(
                    title: "Scanning \(model.currentTarget?.name ?? "disk")\(scan.isAdministrator ? " as administrator" : "")",
                    detail: scanDetail(scan),
                    fraction: scan.fraction,
                    onCancel: { model.currentTarget.map { model.analyze.cancel($0.id) } }
                )
            }
            ZStack {
                if navigator.analyzeMode == .changes {
                    ChangesView()
                } else if navigator.analyzeMode == .duplicates {
                    DuplicatesView()
                } else if let tree = model.currentScan?.tree, navigator.analyzeMode == .sunburst {
                    SunburstView(tree: tree, focus: model.focusNode, unaccountedBytes: model.unaccountedBytes)
                        .animation(.easeOut(duration: 0.25), value: model.focusNode)
                } else if let tree = model.currentScan?.tree, navigator.analyzeMode == .files {
                    LargestFilesView(tree: tree, focus: model.focusNode)
                } else if let tree = model.currentScan?.tree {
                    TreemapView(
                        tree: tree, focus: model.focusNode, unaccountedBytes: model.unaccountedBytes,
                        depth: min(max(depth, 1), 4), selectedPath: navigator.selectedPath
                    )
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.surface)
                    ProgressView().controlSize(.large)
                }
            }
        }
    }

    private func scanDetail(_ scan: ScanState) -> String {
        let files = "\(scan.progress.filesScanned.formatted()) files"
        guard let expected = scan.expectedBytes, let fraction = scan.fraction else {
            return "\(files) · \(ByteSize.format(scan.progress.bytesScanned))"
        }
        return "\(files) · \(ByteSize.format(scan.progress.bytesScanned)) of about \(ByteSize.format(expected)) · \(Int(fraction * 100))%"
    }
}

struct TreemapView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    let tree: DiskTree
    let focus: DiskTree.NodeID
    let unaccountedBytes: Int64
    let depth: Int
    let selectedPath: String?

    @State private var hoveredID: Int?
    @State private var cache = LayoutCache<LayoutKey, [TreemapTile]>()
    private let captionHeight: CGFloat = 16

    private struct LayoutKey: Hashable {
        var nodes: Int
        var focus: DiskTree.NodeID
        var size: Int64
        var unaccounted: Int64
        var depth: Int
        var width: CGFloat
        var height: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height - captionHeight - Theme.Spacing.xs, 0)
            let key = LayoutKey(
                nodes: tree.nodeCount, focus: focus, size: tree.size(focus), unaccounted: unaccountedBytes,
                depth: depth, width: proxy.size.width, height: height
            )
            let tiles = cache.value(for: key) {
                TreemapLayout.tiles(
                    for: tree, focus: focus, in: CGRect(x: 0, y: 0, width: proxy.size.width, height: height),
                    configuration: TreemapConfiguration(maxDepth: depth), unaccountedBytes: unaccountedBytes
                )
            }
            let hovered = hoveredID.flatMap { id in tiles.first { $0.id == id } }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ZStack {
                    StaticCanvas(key: key) { context in
                        for tile in tiles { draw(tile, in: &context) }
                    }
                    .equatable()
                    // Only the highlight depends on hover, so only this layer redraws while the pointer moves.
                    Canvas { context, _ in
                        for tile in tiles where tile.id == hoveredID || isSelected(tile) {
                            context.stroke(shape(tile), with: .color(Theme.tileHoverStroke), lineWidth: 2)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .fileDrag { point in
                    guard let target = TreemapLayout.hitTest(tiles, at: point), let node = target.node else { return nil }
                    return FileDragItem(
                        path: tree.realPath(node), title: target.title, size: target.size,
                        isDirectory: tree.isDirectory(node), tint: Theme.treemapColor(target.colorIndex)
                    )
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let id = TreemapLayout.hitTest(tiles, at: point)?.id
                        if id != hoveredID { hoveredID = id }
                    case .ended: hoveredID = nil
                    }
                }
                .onTapGesture { point in
                    if let tile = TreemapLayout.hitTest(tiles, at: point) { open(tile) }
                }
                .contextMenu {
                    if let hovered, let node = hovered.node {
                        NodeActions(
                            path: tree.displayPath(node), size: tree.size(node),
                            isDirectory: tree.isDirectory(node), canOpen: tree.canOpen(node)
                        )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Treemap of \(tree.displayPath(focus))")
                .accessibilityChildren { accessibleTiles(tiles) }

                Text(caption(hovered))
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: captionHeight)
            }
        }
    }

    private func open(_ tile: TreemapTile) {
        switch tile.content {
        case .unaccounted:
            navigator.present(.hiddenSpace)
            return
        case .others(let parent, _), .looseFiles(let parent):
            // The folder holding these small items shows them at full size.
            if parent != focus { navigator.focus(tree.displayPath(parent)) }
            return
        case .node:
            break
        }
        guard let node = tile.node else { return }
        if tree.canOpen(node) {
            navigator.focus(tree.displayPath(node))
        } else {
            navigator.select(tree.displayPath(node))
        }
    }

    private func caption(_ tile: TreemapTile?) -> String {
        guard let tile else { return "Click a folder to open it. Right-click for more, like moving it to an external drive." }
        switch tile.content {
        case .node(let node):
            let items = tree.isDirectory(node) ? " · \(tree.itemCount(node).formatted()) items" : ""
            let change = model.currentComparison?.delta(atDisplayPath: tree.displayPath(node)).map(changeText) ?? ""
            return "\(tree.displayPath(node)) · \(ByteSize.format(tile.size))\(items)\(change)"
        case .looseFiles: return "Files directly in this folder · \(ByteSize.format(tile.size))"
        case .others(let parent, let count):
            let hint = parent == focus ? "see Largest Files or the sidebar" : "click to open \(tree.name(parent))"
            return "\(count) smaller items · \(ByteSize.format(tile.size)) · \(hint)"
        case .unaccounted: return "macOS, snapshots and space the scan can't see · \(ByteSize.format(tile.size)) · click for a breakdown"
        }
    }

    private func changeText(_ delta: Int64) -> String {
        guard abs(delta) >= 1_000_000 else { return "" }
        return " · \(delta > 0 ? "+" : "−")\(ByteSize.format(abs(delta))) since last scan"
    }

    private func isSelected(_ tile: TreemapTile) -> Bool {
        guard let node = tile.node else { return false }
        let path = tree.displayPath(node)
        return path == selectedPath || path == navigator.hoveredPath
    }

    private func shape(_ tile: TreemapTile) -> Path {
        RoundedRectangle(cornerRadius: tile.depth == 1 ? Theme.Radius.tile + 2 : Theme.Radius.tile, style: .continuous)
            .path(in: tile.rect)
    }

    private func draw(_ tile: TreemapTile, in context: inout GraphicsContext) {
        let isNeutral = tile.content == .unaccounted
        context.fill(shape(tile), with: .color(Theme.treemapFill(
            colorIndex: tile.colorIndex, depth: tile.depth, isContainer: tile.isContainer, isNeutral: isNeutral
        )))
        if tile.isContainer {
            drawHeader(tile, in: &context)
        } else {
            drawLabel(tile, in: &context)
        }
    }

    private func drawHeader(_ tile: TreemapTile, in context: inout GraphicsContext) {
        let available = tile.rect.width - 16
        let size = context.resolve(
            Text(ByteSize.format(tile.size)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
        )
        let sizeWidth = size.measure(in: .unbounded).width
        let showsSize = available > sizeWidth + 60
        guard let title = fitted(tile.title, width: available - (showsSize ? sizeWidth + 8 : 0), in: context, text: {
            Text($0).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tileHeaderText)
        }) else { return }
        let origin = CGPoint(x: tile.rect.minX + 8, y: tile.rect.minY + 4)
        var clipped = context
        clipped.clip(to: Path(CGRect(x: tile.rect.minX, y: tile.rect.minY, width: tile.rect.width - 6, height: 20)))
        clipped.draw(title, at: origin, anchor: .topLeading)
        if showsSize {
            let titleWidth = title.measure(in: .unbounded).width
            clipped.draw(size, at: CGPoint(x: origin.x + titleWidth + 8, y: origin.y + 1), anchor: .topLeading)
        }
    }

    private func drawLabel(_ tile: TreemapTile, in context: inout GraphicsContext) {
        let rect = tile.rect
        guard rect.width > 44, rect.height > 22 else { return }
        let large = rect.width > 220 && rect.height > 120
        let symbol: String
        switch tile.content {
        case .node(let node): symbol = tree.isDirectory(node) ? "folder" : "doc"
        case .unaccounted: symbol = "gearshape"
        case .others: symbol = "square.stack"
        case .looseFiles: symbol = "doc.on.doc"
        }
        let titleSize: CGFloat = large ? 20 : 12
        let available = rect.width - 20
        // Prefer icon + name; drop the icon before cutting the name short.
        let title = fitted(tile.title, width: available, in: context, minimumCharacters: 6) {
            Text("\(Image(systemName: symbol)) \($0)").font(.system(size: titleSize, weight: .medium)).foregroundStyle(Theme.textOnTile)
        } ?? fitted(tile.title, width: available, in: context) {
            Text($0).font(.system(size: titleSize, weight: .medium)).foregroundStyle(Theme.textOnTile)
        }
        guard let title else { return }
        let size = context.resolve(
            Text(ByteSize.format(tile.size))
                .font(.system(size: large ? 15 : 11, design: .monospaced))
                .foregroundStyle(Theme.tileSecondaryText)
        )
        let showsSize = rect.height > (large ? 70 : 40) && size.measure(in: .unbounded).width <= available
        let center = CGPoint(x: rect.midX, y: rect.midY - (showsSize ? titleSize * 0.6 : 0))
        // Backstop: never paint outside the tile, even if a measurement is off.
        var clipped = context
        clipped.clip(to: Path(rect.insetBy(dx: 2, dy: 2)))
        clipped.draw(title, at: center, anchor: .center)
        if showsSize {
            clipped.draw(size, at: CGPoint(x: rect.midX, y: center.y + titleSize + 4), anchor: .center)
        }
    }

    /// The longest prefix of `string` (with "…") whose text fits `width`; nil if even a few characters don't.
    private func fitted(
        _ string: String, width: CGFloat, in context: GraphicsContext, minimumCharacters: Int = 2,
        text: (String) -> Text
    ) -> GraphicsContext.ResolvedText? {
        guard width > 0 else { return nil }
        let full = context.resolve(text(string))
        if full.measure(in: .unbounded).width <= width { return full }
        var low = minimumCharacters
        var high = string.count - 1
        var best: GraphicsContext.ResolvedText?
        while low <= high {
            let middle = (low + high) / 2
            let candidate = context.resolve(text(String(string.prefix(middle)) + "…"))
            if candidate.measure(in: .unbounded).width <= width {
                best = candidate
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return best
    }

    @ViewBuilder
    private func accessibleTiles(_ tiles: [TreemapTile]) -> some View {
        ForEach(tiles.filter { $0.depth == 1 }) { tile in
            Rectangle()
                .accessibilityLabel("\(tile.title), \(ByteSize.format(tile.size))")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open(tile) }
        }
    }
}
