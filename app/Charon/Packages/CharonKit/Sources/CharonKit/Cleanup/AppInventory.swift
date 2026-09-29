// Cleanup/AppInventory.swift
// CharonKit
//
// Installed apps and the files they leave in ~/Library, matched by bundle ID (and name for a few folders).

import CoreServices
import Foundation

public struct InstalledApp: Sendable, Hashable, Identifiable {
    public var url: URL
    public var name: String
    public var bundleID: String
    public var version: String?
    public var bytes: Int64
    public var lastUsed: Date?
    public var id: String { url.path }
}

public struct AppLeftover: Sendable, Hashable, Identifiable {
    public var url: URL
    public var kind: String
    public var bytes: Int64
    /// Matched loosely (by app name, or a longer ID that starts with this app's), so it might belong to another app.
    public var isUncertain: Bool
    public var id: String { url.path }
}

public struct AppInventory: Sendable {
    public var homeDirectory: URL
    public var appFolders: [URL]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        appFolders: [URL]? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.appFolders = appFolders ?? [
            URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"),
            homeDirectory.appendingPathComponent("Applications")
        ]
    }

    /// Third-party apps, largest first. Apple's own apps and Charon are left out.
    public func apps() async -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for url in appBundles() {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespaces),
                  Self.isUsableBundleID(bundleID), !bundleID.hasPrefix("com.apple."), bundleID != "dev.houwert.charon" else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let bytes = (try? await CleanMeasurer.size(of: url)) ?? 0
            apps.append(InstalledApp(
                url: url, name: name, bundleID: bundleID,
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                bytes: bytes, lastUsed: Self.lastUsedDate(url)
            ))
        }
        return apps.sorted { $0.bytes > $1.bytes }
    }

    func appBundles() -> [URL] {
        appFolders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { folder.appendingPathComponent($0) }
        }
    }

    /// Existing leftovers for `app`, largest first.
    public func leftovers(for app: InstalledApp) async -> [AppLeftover] {
        var found: [AppLeftover] = []
        for candidate in candidates(bundleID: app.bundleID, name: app.name) {
            let bytes = (try? await CleanMeasurer.size(of: candidate.url)) ?? 0
            found.append(AppLeftover(url: candidate.url, kind: candidate.kind, bytes: bytes, isUncertain: candidate.uncertain))
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    /// Paths that belong to the app and exist right now.
    struct Candidate {
        var url: URL
        var kind: String
        var uncertain = false
    }

    /// An empty or malformed ID would turn "Containers/<id>" into all of Containers.
    static func isUsableBundleID(_ id: String) -> Bool {
        id.count >= 3 && id.contains(".") && !id.contains("/") && !id.hasPrefix(".") && !id.hasSuffix(".")
    }

    /// How a folder entry relates to the bundle ID: nil (unrelated), certain, or uncertain.
    static func fuzzyMatch(_ entry: String, bundleID id: String, folder: String) -> Bool? {
        let stem = entry.hasSuffix(".plist") ? String(entry.dropLast(6)) : entry
        if stem == id { return false }
        switch folder {
        case "Group Containers":
            // "<TEAMID>.<bundle id>"
            if stem.hasSuffix("." + id), !stem.dropLast(id.count + 1).contains(".") { return false }
        case "Preferences/ByHost":
            // "<bundle id>.<hardware UUID>"
            if stem.hasPrefix(id + "."), UUID(uuidString: String(stem.dropFirst(id.count + 1))) != nil { return false }
        default:
            break
        }
        // Helpers ("<id>.helper") but also sibling apps ("<id>.beta"): show, but don't preselect.
        return stem.hasPrefix(id + ".") || stem.hasSuffix("." + id) ? true : nil
    }

    func candidates(bundleID: String, name: String) -> [Candidate] {
        guard Self.isUsableBundleID(bundleID) else { return [] }
        let name = name.contains("/") || name.trimmingCharacters(in: .whitespaces).isEmpty ? bundleID : name
        let library = homeDirectory.appendingPathComponent("Library")
        func at(_ relative: String) -> URL { library.appendingPathComponent(relative) }

        var exact: [Candidate] = [
            Candidate(url: at("Application Support/\(bundleID)"), kind: "Application Support"),
            Candidate(url: at("Application Support/\(name)"), kind: "Application Support", uncertain: true),
            Candidate(url: at("Caches/\(bundleID)"), kind: "Caches"),
            Candidate(url: at("Caches/\(name)"), kind: "Caches", uncertain: true),
            Candidate(url: at("Containers/\(bundleID)"), kind: "Container"),
            Candidate(url: at("Application Scripts/\(bundleID)"), kind: "Scripts"),
            Candidate(url: at("Preferences/\(bundleID).plist"), kind: "Preferences"),
            Candidate(url: at("Saved Application State/\(bundleID).savedState"), kind: "Saved state"),
            Candidate(url: at("HTTPStorages/\(bundleID)"), kind: "Web data"),
            Candidate(url: at("HTTPStorages/\(bundleID).binarycookies"), kind: "Web data"),
            Candidate(url: at("WebKit/\(bundleID)"), kind: "Web data"),
            Candidate(url: at("Cookies/\(bundleID).binarycookies"), kind: "Web data"),
            Candidate(url: at("Logs/\(bundleID)"), kind: "Logs"),
            Candidate(url: at("Logs/\(name)"), kind: "Logs", uncertain: true)
        ]
        // Folders where the bundle ID is embedded (team-prefixed group containers, versioned agents, per-host prefs).
        let fuzzy: [(String, String)] = [
            ("Group Containers", "Group container"), ("LaunchAgents", "Launch agent"), ("Preferences/ByHost", "Preferences")
        ]
        for (folder, kind) in fuzzy {
            let directory = at(folder)
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
                guard let uncertain = Self.fuzzyMatch(entry, bundleID: bundleID, folder: folder) else { continue }
                exact.append(Candidate(url: directory.appendingPathComponent(entry), kind: kind, uncertain: uncertain))
            }
        }
        var seen = Set<String>()
        return exact.filter { candidate in
            FileManager.default.fileExists(atPath: candidate.url.path) && seen.insert(candidate.url.path).inserted
        }
    }

    /// Spotlight's last-opened date; nil for items never opened or not indexed.
    public static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
