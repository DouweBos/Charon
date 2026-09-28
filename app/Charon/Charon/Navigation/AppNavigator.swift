// Navigation/AppNavigator.swift
// Charon
//
// The single owner of what's on screen: tab, disk, drill-down path and selection. Every change is a
// history entry, so back/forward work everywhere.

import Foundation
import Observation

enum AppTab: String, CaseIterable, Hashable {
    case analyze, offload, clean, uninstall, optimize

    var title: String {
        switch self {
        case .analyze: "Analyze"
        case .offload: "Offload"
        case .clean: "Clean"
        case .uninstall: "Uninstall"
        case .optimize: "Optimize"
        }
    }

    var symbol: String {
        switch self {
        case .analyze: "waveform.path.ecg"
        case .offload: "externaldrive.badge.plus"
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

enum AnalyzeMode: String, CaseIterable, Hashable {
    case map, sunburst, files, changes, duplicates

    var title: String {
        switch self {
        case .map: "Map"
        case .sunburst: "Rings"
        case .files: "Largest Files"
        case .changes: "Changes"
        case .duplicates: "Duplicates"
        }
    }
}

struct NavigationLocation: Hashable {
    var tab: AppTab = .analyze
    var targetID: String?
    /// Display path of the drilled-into directory; nil is the volume root.
    var focusPath: String?
    var analyzeMode: AnalyzeMode = .map
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
    var targetID: String? { location.targetID }
    var focusPath: String? { location.focusPath }
    var analyzeMode: AnalyzeMode { location.analyzeMode }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }

    func selectTab(_ tab: AppTab) {
        var next = location
        next.tab = tab
        push(next)
    }

    func selectTarget(_ id: String) {
        guard id != targetID else { return }
        push(NavigationLocation(tab: .analyze, targetID: id, focusPath: nil))
    }

    /// Adopts a volume without a history entry (initial load, or the current disk was ejected).
    func setDefaultTarget(_ id: String?) {
        history[index].targetID = id
        history[index].focusPath = nil
    }

    func focus(_ path: String?, mode: AnalyzeMode? = nil) {
        var next = location
        next.tab = .analyze
        next.focusPath = path
        if let mode { next.analyzeMode = mode }
        push(next)
    }

    /// Shows `path` selected inside its parent on `targetID`, in one history entry.
    func reveal(_ path: String, in targetID: String) {
        var next = location
        next.tab = .analyze
        next.targetID = targetID
        let parent = (path as NSString).deletingLastPathComponent
        next.focusPath = parent == "/" ? nil : parent
        if next.analyzeMode != .sunburst { next.analyzeMode = .map }
        push(next)
        selectedPath = path
    }

    func setAnalyzeMode(_ mode: AnalyzeMode) {
        var next = location
        next.tab = .analyze
        next.analyzeMode = mode
        push(next)
    }

    func select(_ path: String?) {
        selectedPath = path
    }

    /// Folder under the pointer in the rings; the sidebar shows its contents while it's set.
    private(set) var peekPath: String?
    /// The peeked segment's color, so the sidebar's dots match the rings.
    private(set) var peekColorIndex = 0
    /// Set when the peeked segment is a group of small items in `peekPath`: only entries below this size.
    private(set) var peekGroupedBelow: Int64?
    /// Set when the peeked segment is the loose files directly in `peekPath`.
    private(set) var peekIsLooseFiles = false

    func peek(_ path: String?, colorIndex: Int = 0, groupedBelow: Int64? = nil, looseFiles: Bool = false) {
        guard peekPath != path || peekGroupedBelow != groupedBelow || peekIsLooseFiles != looseFiles else { return }
        peekPath = path
        peekColorIndex = colorIndex
        peekGroupedBelow = groupedBelow
        peekIsLooseFiles = looseFiles
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
