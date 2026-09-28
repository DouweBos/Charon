// App/AppDelegate.swift
// Charon
//
// Receives folders opened with Charon. They can arrive before the model is wired up, so they queue.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpen: (([URL]) -> Void)? {
        didSet {
            guard let onOpen, !pending.isEmpty else { return }
            onOpen(pending)
            pending = []
        }
    }
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate()
        // SwiftUI keeps the closed main window around; bring it back so the folder is visible.
        if !NSApp.windows.contains(where: \.isVisible) {
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil)
        }
        if let onOpen { onOpen(urls) } else { pending += urls }
    }
}
