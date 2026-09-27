// Offload/OffloadPreflight.swift
// CharonKit
//
// Decides whether a directory may be offloaded. Blockers stop the offload; warnings need the user's consent.

import Darwin
import Foundation

public struct PreflightIssue: Sendable, Hashable, Identifiable {
    public enum Severity: Sendable, Hashable { case blocker, warning }

    public var severity: Severity
    public var message: String
    public var id: String { message }
}

public struct PreflightReport: Sendable, Hashable {
    public var source: URL
    public var bytes: Int64
    public var issues: [PreflightIssue]

    public var blockers: [PreflightIssue] { issues.filter { $0.severity == .blocker } }
    public var warnings: [PreflightIssue] { issues.filter { $0.severity == .warning } }
    public var canOffload: Bool { blockers.isEmpty }
}

public struct OffloadPreflight: Sendable {
    public var homeDirectory: URL
    public var resolver: any VolumeResolving
    public var inspector: any ProcessInspecting

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        resolver: any VolumeResolving = VolumeCatalog(),
        inspector: any ProcessInspecting = ProcessInspector()
    ) {
        self.homeDirectory = homeDirectory
        self.resolver = resolver
        self.inspector = inspector
    }

    /// System locations; the directory itself and everything inside is refused.
    static let systemRoots = [
        "/System", "/bin", "/sbin", "/usr", "/private", "/etc", "/var", "/tmp", "/dev", "/cores", "/Volumes", "/.vol",
        "/Library/Apple", "/Library/Extensions", "/Library/Frameworks", "/Library/Keychains",
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/Preferences", "/Library/Security"
    ]
    static let systemExceptions = ["/usr/local"]
    /// Containers that must stay real directories, though their children may be offloaded.
    static let exactRoots = ["/", "/Applications", "/Library", "/Users", "/opt", "/usr/local", "/opt/homebrew"]

    /// Home-relative locations apps or macOS refuse to follow symlinks out of.
    static let homeRoots = [
        "Library/Keychains", "Library/Containers", "Library/Group Containers", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Preferences", "Library/Metadata", "Library/Daemon Containers",
        "Library/Application Support/com.apple.TCC", "Library/Application Support/Charon", "Library/Accounts",
        "Library/Biome", "Library/Messages", "Library/Mail", ".Trash"
    ]
    static let homeExactRoots = ["", "Library", "Library/Application Support", "Library/Caches", "Desktop", "Documents"]

    /// SF_RESTRICTED: SIP-protected.
    private static let restrictedFlag: UInt32 = 0x0008_0000

    public func check(
        source: URL, drive: VolumeInfo?, bytes knownBytes: Int64? = nil, existing: [OffloadRecord] = []
    ) async -> PreflightReport {
        let path = Self.userFacingPath(source.standardizedFileURL.path)
        var issues: [PreflightIssue] = []
        func block(_ message: String) { issues.append(PreflightIssue(severity: .blocker, message: message)) }
        func warn(_ message: String) { issues.append(PreflightIssue(severity: .warning, message: message)) }

        var info = stat()
        guard lstat(path, &info) == 0 else {
            return PreflightReport(source: source, bytes: 0, issues: [PreflightIssue(severity: .blocker, message: "It no longer exists.")])
        }
        if info.st_mode & S_IFMT == S_IFLNK { block("It's already a symlink.") }
        if info.st_mode & S_IFMT != S_IFDIR { block("Only directories can be offloaded.") }

        issues += pathRules(path).map { PreflightIssue(severity: $0.0, message: $0.1) }

        var parentInfo = stat()
        let parent = (path as NSString).deletingLastPathComponent
        if info.st_flags & Self.restrictedFlag != 0
            || (lstat(parent, &parentInfo) == 0 && parentInfo.st_flags & Self.restrictedFlag != 0) {
            block("It's protected by System Integrity Protection.")
        }
        if access(parent, W_OK) != 0 || access(path, W_OK) != 0 {
            block("It needs administrator rights to move.")
        }

        issues += existing.compactMap { Self.overlap(path, with: $0) }

        let usages = inspector.processes(using: path)
        let running = usages.filter { $0.reason == .runningFromHere }
        if !running.isEmpty {
            block("\(Self.names(running)) is running from here. Quit it first.")
        }
        let open = usages.filter { $0.reason != .runningFromHere }
        if !open.isEmpty {
            warn("\(Self.names(open)) has files open in here. Quit it before offloading, or changes may be lost.")
        }

        let bytes: Int64
        if let knownBytes { bytes = knownBytes } else { bytes = (try? OffloadEngine.measure(URL(fileURLWithPath: path)).bytes) ?? 0 }
        issues += driveRules(drive: drive, sourcePath: path, bytes: bytes)

        return PreflightReport(source: URL(fileURLWithPath: path), bytes: bytes, issues: issues)
    }

    static func overlap(_ path: String, with record: OffloadRecord) -> PreflightIssue? {
        let message: String
        if record.originalPath == path {
            message = "It's already offloaded."
        } else if path.hasPrefix(record.originalPath + "/") {
            message = "It's inside \(record.name), which is already offloaded."
        } else if record.originalPath.hasPrefix(path + "/") {
            message = "It contains \(record.name), which is already offloaded. Move that back first."
        } else {
            return nil
        }
        return PreflightIssue(severity: .blocker, message: message)
    }

    func pathRules(_ path: String) -> [(PreflightIssue.Severity, String)] {
        let home = homeDirectory.standardizedFileURL.path
        func within(_ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
        var rules: [(PreflightIssue.Severity, String)] = []

        if Self.systemRoots.contains(where: within), !Self.systemExceptions.contains(where: within) {
            rules.append((.blocker, "It's a macOS system location."))
        }
        if Self.exactRoots.contains(path) || Self.homeExactRoots.map({ Self.join(home, $0) }).contains(path) {
            rules.append((.blocker, "This folder must stay a real directory. Offload something inside it instead."))
        }
        if Self.homeRoots.map({ Self.join(home, $0) }).contains(where: within) {
            rules.append((.blocker, "macOS or sandboxed apps won't follow a symlink here."))
        }
        let components = path.split(separator: "/")
        if components.dropLast().contains(where: { Self.isBundle($0) }) {
            rules.append((.blocker, "It's inside an app or bundle, which would break its code signature."))
        } else if let last = components.last, Self.isBundle(last) {
            rules.append((.blocker, "App bundles can't be offloaded; macOS won't launch them through a symlink reliably."))
        }
        if within(Self.join(home, "Library")), rules.isEmpty {
            rules.append((.warning, "Apps store live data in Library. Quit the app that owns it before offloading."))
        }
        if within("/opt/homebrew") || within("/usr/local") {
            rules.append((.warning, "Package managers may relink or rewrite this; updates can break the symlink."))
        }
        return rules
    }

    func driveRules(drive: VolumeInfo?, sourcePath: String, bytes: Int64) -> [PreflightIssue] {
        guard let drive else { return [PreflightIssue(severity: .blocker, message: "Choose an External Drive first.")] }
        var issues: [PreflightIssue] = []
        if !drive.canBeOffloadDrive {
            issues.append(PreflightIssue(severity: .blocker, message: "\(drive.name) can't be an External Drive."))
        }
        if let sourceVolume = resolver.volume(containing: URL(fileURLWithPath: sourcePath)), sourceVolume.id == drive.id {
            issues.append(PreflightIssue(severity: .blocker, message: "It's already on \(drive.name)."))
        }
        if drive.uuid == nil {
            issues.append(PreflightIssue(severity: .blocker, message: "\(drive.name) has no volume UUID, so it can't be tracked."))
        }
        let margin: Int64 = 1_000_000_000
        if drive.availableBytes < bytes + margin {
            issues.append(PreflightIssue(
                severity: .blocker,
                message: "\(drive.name) needs \(ByteSize.format(bytes + margin)) free (\(ByteSize.format(drive.availableBytes)) available)."
            ))
        }
        if !drive.preservesMetadata {
            issues.append(PreflightIssue(
                severity: .warning,
                message: "\(drive.name) is \(drive.fileSystem.uppercased()), which drops permissions and extended attributes."
            ))
        }
        return issues
    }

    /// `/System/Volumes/Data/Users/x` → `/Users/x`: the firmlinked path is what apps and symlinks use.
    public static func userFacingPath(_ path: String) -> String {
        let data = "/System/Volumes/Data"
        guard path.hasPrefix(data + "/") else { return path }
        return String(path.dropFirst(data.count))
    }

    private static func isBundle(_ component: Substring) -> Bool {
        [".app", ".bundle", ".framework", ".kext", ".plugin", ".appex", ".xpc"].contains { component.hasSuffix($0) }
    }

    private static func join(_ base: String, _ relative: String) -> String {
        relative.isEmpty ? base : base + "/" + relative
    }

    private static func names(_ usages: [ProcessUsage]) -> String {
        let names = Array(Set(usages.map(\.name))).sorted()
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) and \(names.count - 3) more" : shown
    }
}
