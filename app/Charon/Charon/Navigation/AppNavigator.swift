// Navigation/AppNavigator.swift
// Charon
//
// The single owner of what's on screen: tab, disk, drill-down path and selection. Every change is a
// history entry, so back/forward work everywhere.

import Foundation
import Observation

enum AppTab: String, CaseIterable, Hashable {
    case analyze, ferry, clean, uninstall, optimize

    var title: String {
        switch self {
        case .analyze: "Analyze"
        case .ferry: "Ferry"
        case .clean: "Clean"
        case .uninstall: "Uninstall"
        case .optimize: "Optimize"
        }
    }

    var symbol: String {
        switch self {
        case .analyze: "waveform.path.ecg"
        case .ferry: "ferry"
        case .clean: "sparkles"
        case .uninstall: "trash"
        case .optimize: "leaf"
        }
    }
}

/// Modal panels that aren't tied to a ViewModel's own flow.
enum AppSheet: String, Identifiable {
    case fullDiskAccess
    case restrictedFolders
    case hiddenSpace

    var id: String { rawValue }
}

struct NavigationLocation: Hashable {
    var tab: AppTab = .analyze
    var volumeID: String?
    /// Display path of the drilled-into directory; nil is the volume root.
    var focusPath: String?
}

@MainActor
@Observable
final class AppNavigator {
    private(set) var history: [NavigationLocation]
    private(set) var index = 0
    /// Highlighted item (hover-independent), shared by sidebar and treemap.
    private(set) var selectedPath: String?
    private(set) var sheet: AppSheet?
    /// Pointer-hovered item; drawn like the selection but never replaces it.
    private(set) var hoveredPath: String?
    /// Item shown in Quick Look.
    private(set) var previewPath: String?

    init() {
        history = [NavigationLocation()]
    }

    var location: NavigationLocation { history[index] }
    var tab: AppTab { location.tab }
    var volumeID: String? { location.volumeID }
    var focusPath: String? { location.focusPath }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }

    func selectTab(_ tab: AppTab) {
        var next = location
        next.tab = tab
        push(next)
    }

    func selectVolume(_ id: String) {
        guard id != volumeID else { return }
        push(NavigationLocation(tab: .analyze, volumeID: id, focusPath: nil))
    }

    /// Adopts a volume without a history entry (initial load, or the current disk was ejected).
    func setDefaultVolume(_ id: String?) {
        history[index].volumeID = id
        history[index].focusPath = nil
    }

    func focus(_ path: String?) {
        guard path != focusPath || tab != .analyze else { return }
        var next = location
        next.tab = .analyze
        next.focusPath = path
        push(next)
    }

    func select(_ path: String?) {
        selectedPath = path
    }

    func hover(_ path: String?) {
        hoveredPath = path
    }

    func togglePreview(_ path: String) {
        previewPath = previewPath == path ? nil : path
    }

    func closePreview() {
        previewPath = nil
    }

    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    func dismissSheet() {
        sheet = nil
    }

    func goBack() {
        guard canGoBack else { return }
        index -= 1
        selectedPath = nil
    }

    func goForward() {
        guard canGoForward else { return }
        index += 1
        selectedPath = nil
    }

    private func push(_ next: NavigationLocation) {
        guard next != location else { return }
        history.removeSubrange((index + 1)...)
        history.append(next)
        index = history.count - 1
        selectedPath = nil
    }
}
