// Utilities/SystemIntegration.swift
// Charon
//
// Finder, System Settings and Full Disk Access helpers.

import AppKit
import Foundation

enum SystemIntegration {

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// TCC-protected files can only be opened with Full Disk Access; there's no API to ask directly.
    static var hasFullDiskAccess: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probes = [
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Safari/CloudTabs.db",
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            if errno == EPERM || errno == EACCES { return false }
        }
        return false
    }

    static func chooseDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
