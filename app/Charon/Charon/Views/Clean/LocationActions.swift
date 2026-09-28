// Views/Clean/LocationActions.swift
// Charon
//
// Context menu for a place on disk found outside Analyze: open it in the Map or Rings, or in Finder.

import AppKit
import CharonKit
import SwiftUI

struct LocationActions: View {
    let locations: [URL]

    var body: some View {
        if locations.count == 1, let url = locations.first {
            LocationButtons(url: url)
        } else {
            ForEach(locations.prefix(20), id: \.self) { url in
                Menu(LocationActions.display(url)) { LocationButtons(url: url) }
            }
        }
    }

    /// The path with the home folder as ~.
    static func display(_ url: URL) -> String {
        (OffloadPreflight.userFacingPath(url.path) as NSString).abbreviatingWithTildeInPath
    }
}

private struct LocationButtons: View {
    @Environment(AppModel.self) private var model
    let url: URL

    var body: some View {
        Button("Show in Map", systemImage: "square.grid.2x2") { model.showInAnalyze(url, mode: .map) }
        Button("Show in Rings", systemImage: "circle.circle") { model.showInAnalyze(url, mode: .sunburst) }
        Button("Reveal in Finder", systemImage: "folder") { SystemIntegration.revealInFinder(url.path) }
        Button("Copy Path", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }
}
