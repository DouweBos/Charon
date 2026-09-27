// Startup/LaunchItemInventory.swift
// CharonKit
//
// Launch agents and daemons: what starts in the background, whether it's running, and whether the program
// it points at still exists (a missing one is usually left behind by an uninstalled app).

import Foundation

public struct LaunchItem: Sendable, Hashable, Identifiable {
    public enum Scope: String, Sendable, CaseIterable {
        case user = "Your agents"
        case systemAgent = "Agents for all users"
        case systemDaemon = "System daemons"
    }

    public var url: URL
    public var scope: Scope
    public var label: String
    public var program: String?
    public var programExists: Bool
    public var runsAtLoad: Bool
    public var keepsAlive: Bool
    public var isDisabled: Bool
    public var isRunning: Bool
    /// The app bundle the program lives in, if any.
    public var owningApp: String?

    public var id: String { url.path }
    public var isOrphaned: Bool { program != nil && !programExists }
}

public struct LaunchItemInventory: Sendable {
    public var homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func items(runningLabels: Set<String> = []) -> [LaunchItem] {
        let folders: [(URL, LaunchItem.Scope)] = [
            (homeDirectory.appendingPathComponent("Library/LaunchAgents"), .user),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .systemAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .systemDaemon)
        ]
        return folders.flatMap { folder, scope in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.hasSuffix(".plist") }
                .sorted()
                .compactMap { name -> LaunchItem? in
                    let url = folder.appendingPathComponent(name)
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return Self.parse(data, url: url, scope: scope, runningLabels: runningLabels)
                }
        }
    }

    public static func parse(_ data: Data, url: URL, scope: LaunchItem.Scope, runningLabels: Set<String>) -> LaunchItem? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let keepAlive: Bool
        switch plist["KeepAlive"] {
        case let value as Bool: keepAlive = value
        case is [String: Any]: keepAlive = true
        default: keepAlive = false
        }
        return LaunchItem(
            url: url, scope: scope, label: label, program: program,
            programExists: program.map { FileManager.default.fileExists(atPath: $0) } ?? true,
            runsAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepsAlive: keepAlive,
            isDisabled: plist["Disabled"] as? Bool ?? false,
            isRunning: runningLabels.contains(label),
            owningApp: program.flatMap(appName)
        )
    }

    /// Labels with a live process in the current user's launchd domain, from `launchctl list`.
    public static func parseRunningLabels(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").dropFirst().compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3, columns[0] != "-" else { return nil }
            return String(columns[2])
        })
    }

    public static func runningLabels() async -> Set<String> {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["list"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parseRunningLabels(String(bytes: data, encoding: .utf8) ?? "")
        }.value
    }

    static func appName(_ program: String) -> String? {
        guard let range = program.range(of: ".app/") else { return nil }
        return (String(program[..<range.lowerBound]) as NSString).lastPathComponent
    }
}
