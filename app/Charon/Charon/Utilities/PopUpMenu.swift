// Utilities/PopUpMenu.swift
// Charon
//
// A native menu built once when shown. SwiftUI's Menu rebuilds itself while open whenever the view updates,
// which resizes and truncates it; this one stays put.

import AppKit

@MainActor
enum PopUpMenu {
    struct Item {
        var title: String
        var symbol: String
        var isChecked = false
        var action: () -> Void
    }

    struct Section {
        var title: String?
        var items: [Item]
    }

    /// Shows the menu under the mouse pointer.
    static func show(_ sections: [Section]) {
        let menu = NSMenu()
        for (index, section) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            if let title = section.title { menu.addItem(.sectionHeader(title: title)) }
            for item in section.items {
                let menuItem = ClosureMenuItem(title: item.title, action: item.action)
                menuItem.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
                menuItem.state = item.isChecked ? .on : .off
                menu.addItem(menuItem)
            }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @objc private func run() { handler() }
}
