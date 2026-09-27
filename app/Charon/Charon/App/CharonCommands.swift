// App/CharonCommands.swift
// Charon

import SwiftUI

struct CharonCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Back") { model.navigator.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!model.navigator.canGoBack)
            Button("Forward") { model.navigator.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!model.navigator.canGoForward)
            Button("Enclosing Folder") { model.focusParent() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Divider()
            Button("Rescan") { model.rescanCurrent() }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { model.navigator.selectTab(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
