// Cleanup/CleanCatalog.swift
// CharonKit
//
// Known places where space piles up, with how safe they are to clear. Paths starting with "~" are
// home-relative; a "*" in the last component is a wildcard.

import Foundation

public struct CleanCategory: Sendable, Hashable, Identifiable {
    public enum Group: String, Sendable, CaseIterable {
        case developer = "Developer"
        case packages = "Package Managers"
        case system = "Apps & System"
        case personal = "Personal"
    }

    public enum Safety: Sendable, Hashable {
        /// Rebuilt automatically when needed.
        case regenerated
        /// Recoverable only by re-downloading or can't be recovered; the user should look first.
        case review
    }

    public enum Mode: Sendable, Hashable {
        /// Trash what's inside each path, keep the folder itself.
        case contents
        /// Trash each matched path.
        case itself
        /// Handled by Finder's Empty Trash.
        case emptyTrash
    }

    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var group: Group
    public var safety: Safety
    public var mode: Mode
    public var paths: [String]
    /// Children of `contents` paths that belong to another category.
    public var excludes: [String] = []
}

public enum CleanCatalog {

    public static let all: [CleanCategory] = developer + packages + system + personal

    static let developer: [CleanCategory] = [
        CleanCategory(
            id: "xcode.derivedData", title: "Xcode DerivedData",
            detail: "Build products and indexes. Xcode rebuilds them on the next build.",
            symbol: "hammer", group: .developer, safety: .regenerated, mode: .contents,
            paths: ["~/Library/Developer/Xcode/DerivedData"]
        ),
        CleanCategory(
            id: "xcode.deviceSupport", title: "Device support files",
            detail: "Symbols copied from connected devices. Recreated when a device with that OS is connected again.",
            symbol: "iphone", group: .developer, safety: .regenerated, mode: .contents,
            paths: ["~/Library/Developer/Xcode/*DeviceSupport"]
        ),
        CleanCategory(
            id: "xcode.previews", title: "SwiftUI previews",
            detail: "Preview simulators and caches. Recreated when previews run.",
            symbol: "rectangle.on.rectangle", group: .developer, safety: .regenerated, mode: .contents,
            paths: ["~/Library/Developer/Xcode/UserData/Previews"]
        ),
        CleanCategory(
            id: "simulator.caches", title: "Simulator caches",
            detail: "Dyld and runtime caches for simulators.",
            symbol: "ipad.and.iphone", group: .developer, safety: .regenerated, mode: .contents,
            paths: ["~/Library/Developer/CoreSimulator/Caches"]
        ),
        CleanCategory(
            id: "xcode.archives", title: "Xcode archives",
            detail: "Archived builds with their dSYMs. Needed to symbolicate crashes from shipped versions.",
            symbol: "archivebox", group: .developer, safety: .review, mode: .contents,
            paths: ["~/Library/Developer/Xcode/Archives"]
        )
    ]

    static let packages: [CleanCategory] = [
        package("homebrew", "Homebrew downloads", "~/Library/Caches/Homebrew", "mug"),
        package("swiftpm", "Swift Package Manager", "~/Library/Caches/org.swift.swiftpm", "swift"),
        package("cocoapods", "CocoaPods", "~/Library/Caches/CocoaPods", "shippingbox"),
        package("npm", "npm", "~/.npm/_cacache", "shippingbox"),
        package("yarn", "Yarn", "~/Library/Caches/Yarn", "shippingbox"),
        package("bun", "Bun", "~/.bun/install/cache", "shippingbox"),
        package("pip", "pip", "~/Library/Caches/pip", "shippingbox"),
        package("go", "Go build cache", "~/Library/Caches/go-build", "shippingbox"),
        package("cargo", "Cargo registry cache", "~/.cargo/registry/cache", "shippingbox"),
        package("gradle", "Gradle", "~/.gradle/caches", "shippingbox"),
        CleanCategory(
            id: "package.pnpm", title: "pnpm store",
            detail: "Shared package store. Projects hardlink into it, so space only returns once their node_modules go too.",
            symbol: "shippingbox", group: .packages, safety: .review, mode: .contents,
            paths: ["~/Library/pnpm/store"]
        )
    ]

    static let system: [CleanCategory] = [
        CleanCategory(
            id: "system.caches", title: "App caches",
            detail: "Caches apps rebuild as needed. Quit apps first for the cleanest result.",
            symbol: "internaldrive", group: .system, safety: .regenerated, mode: .contents,
            paths: ["~/Library/Caches"],
            excludes: [
                "~/Library/Caches/Homebrew", "~/Library/Caches/org.swift.swiftpm", "~/Library/Caches/CocoaPods",
                "~/Library/Caches/Yarn", "~/Library/Caches/pip", "~/Library/Caches/go-build", "~/Library/Caches/com.houwert.Charon"
            ]
        ),
        CleanCategory(
            id: "system.logs", title: "Logs",
            detail: "Diagnostic logs written by apps.",
            symbol: "doc.text", group: .system, safety: .regenerated, mode: .contents,
            paths: ["~/Library/Logs"]
        ),
        CleanCategory(
            id: "system.mailDownloads", title: "Mail attachments",
            detail: "Copies of attachments you opened in Mail. The originals stay in your mailbox.",
            symbol: "paperclip", group: .system, safety: .regenerated, mode: .contents,
            paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]
        ),
        CleanCategory(
            id: "system.installers", title: "macOS installers",
            detail: "Downloaded macOS installer apps. They can be downloaded again.",
            symbol: "arrow.down.app", group: .system, safety: .regenerated, mode: .itself,
            paths: ["/Applications/Install macOS*.app"]
        )
    ]

    static let personal: [CleanCategory] = [
        CleanCategory(
            id: "personal.trash", title: "Trash",
            detail: "Emptied through Finder, so it asks before deleting for good.",
            symbol: "trash", group: .personal, safety: .review, mode: .emptyTrash,
            paths: ["~/.Trash"]
        ),
        CleanCategory(
            id: "personal.iosBackups", title: "iPhone and iPad backups",
            detail: "Local device backups. Only remove ones you no longer need.",
            symbol: "iphone.gen3", group: .personal, safety: .review, mode: .contents,
            paths: ["~/Library/Application Support/MobileSync/Backup"]
        )
    ]

    private static func package(_ id: String, _ title: String, _ path: String, _ symbol: String) -> CleanCategory {
        CleanCategory(
            id: "package." + id, title: title, detail: "Downloaded packages. Fetched again when a project needs them.",
            symbol: symbol, group: .packages, safety: .regenerated, mode: .contents, paths: [path]
        )
    }
}

/// Expands a category's paths into the concrete files and folders it would trash.
public struct CleanResolver: Sendable {
    public var homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func expand(_ pattern: String) -> String {
        guard pattern.hasPrefix("~") else { return pattern }
        return homeDirectory.path + pattern.dropFirst()
    }

    /// Existing paths matching `pattern` (wildcard allowed in the last component only).
    public func matches(_ pattern: String) -> [URL] {
        let expanded = expand(pattern)
        let last = (expanded as NSString).lastPathComponent
        guard last.contains("*") else {
            return FileManager.default.fileExists(atPath: expanded) ? [URL(fileURLWithPath: expanded)] : []
        }
        let parent = (expanded as NSString).deletingLastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
        return names.filter { Self.wildcard(last, matches: $0) }.sorted()
            .map { URL(fileURLWithPath: parent).appendingPathComponent($0) }
    }

    /// What cleaning the category would move to the Trash.
    public func items(for category: CleanCategory) -> [URL] {
        let roots = category.paths.flatMap(matches)
        switch category.mode {
        case .itself, .emptyTrash:
            return roots
        case .contents:
            return roots.flatMap { contents(of: $0, excludes: category.excludes) }
        }
    }

    /// Children of `root`, minus excluded paths and Finder metadata.
    public func contents(of root: URL, excludes: [String]) -> [URL] {
        let excluded = Set(excludes.map(expand))
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
            .map { root.appendingPathComponent($0) }
            .filter { !excluded.contains($0.path) && $0.lastPathComponent != ".DS_Store" }
    }

    static func wildcard(_ pattern: String, matches name: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return pattern == name }
        guard name.hasPrefix(parts[0]), name.hasSuffix(parts[parts.count - 1]) else { return false }
        var remainder = Substring(name.dropFirst(parts[0].count))
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let range = remainder.range(of: part) else { return false }
            remainder = remainder[range.upperBound...]
        }
        return remainder.count >= parts[parts.count - 1].count
    }
}
