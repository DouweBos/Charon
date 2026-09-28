// Utilities/FileDrag.swift
// Charon
//
// Drags a file or folder with a DragChip image. SwiftUI's onDrag on macOS ignores custom previews and
// drags a snapshot of the whole view, which for the map or rings is the entire chart.

import AppKit
import SwiftUI

struct FileDragItem {
    var path: String
    var title: String
    var size: Int64
    var isDirectory: Bool
    var tint: Color
}

extension View {
    /// `item` is asked with the point where the drag started; nil means nothing there can be dragged.
    func fileDrag(_ item: @escaping (CGPoint) -> FileDragItem?) -> some View {
        modifier(FileDragModifier(item: item))
    }
}

private struct FileDragModifier: ViewModifier {
    let item: (CGPoint) -> FileDragItem?
    @GestureState private var isDragging = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 6)
                .updating($isDragging) { value, state, _ in
                    guard !state else { return }
                    state = true
                    if let item = item(value.startLocation) { FileDragSession.begin(item, colorScheme: colorScheme) }
                }
        )
    }
}

@MainActor
private enum FileDragSession {
    static func begin(_ item: FileDragItem, colorScheme: ColorScheme) {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView else { return }
        let renderer = ImageRenderer(content: DragChip(
            title: item.title, size: item.size, symbol: item.isDirectory ? "folder" : "doc", tint: item.tint
        ).environment(\.colorScheme, colorScheme))
        renderer.scale = event.window?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let dragging = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: item.path) as NSURL)
        dragging.setDraggingFrame(
            NSRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
                   width: image.size.width, height: image.size.height),
            contents: image
        )
        view.beginDraggingSession(with: [dragging], event: event, source: DragSource.shared)
    }
}

private final class DragSource: NSObject, NSDraggingSource {
    static let shared = DragSource()

    /// Inside Charon the Collector takes it; elsewhere only a link, so a stray drop never copies or moves gigabytes.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : .link
    }
}
