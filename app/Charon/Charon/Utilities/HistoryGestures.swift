// Utilities/HistoryGestures.swift
// Charon
//
// Mouse back/forward buttons and three-finger swipes, as in Finder and Safari.

import AppKit

@MainActor
enum HistoryGestures {
    private static var monitor: Any?

    static func install(back: @escaping @MainActor () -> Void, forward: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { event in
            // Leave sheets and other windows alone.
            guard event.window?.isMainWindow == true, event.window?.attachedSheet == nil else { return event }
            switch event.type {
            case .otherMouseDown where event.buttonNumber == 3: back()
            case .otherMouseDown where event.buttonNumber == 4: forward()
            case .swipe where event.deltaX > 0: back()
            case .swipe where event.deltaX < 0: forward()
            default: return event
            }
            return nil
        }
    }
}
