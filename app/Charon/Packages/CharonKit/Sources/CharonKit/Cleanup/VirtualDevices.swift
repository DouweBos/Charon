// Cleanup/VirtualDevices.swift
// CharonKit
//
// Xcode simulators and Android emulators on disk. Running devices are left out so nothing in use is offered.

import Foundation

public struct VirtualDevice: Sendable, Hashable, Identifiable {
    /// Simulator UDID or AVD name.
    public var id: String
    public var name: String
    /// OS and variant, e.g. "iOS 18.2" or "API 35 · Google Play".
    public var platform: String
    /// The device's data folder.
    public var folder: URL
    /// Other files that belong to the device, e.g. an AVD's `.ini` next to its folder.
    public var companions: [URL] = []
    public var lastUsed: Date?
}

public enum SimulatorDevices {
    /// Shut-down simulators in CoreSimulator's device set under `root`.
    public static func list(root: URL) -> [VirtualDevice] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted().compactMap { name in
            let folder = root.appendingPathComponent(name)
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent("device.plist").path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let udid = plist["UDID"] as? String, let deviceName = plist["name"] as? String else { return nil }
            // State 1 is Shutdown; anything else is booting, booted, or shutting down.
            guard (plist["state"] as? Int) == 1, (plist["isDeleted"] as? Bool) != true else { return nil }
            return VirtualDevice(
                id: udid, name: deviceName, platform: runtimeName(plist["runtime"] as? String ?? ""), folder: folder,
                lastUsed: plist["lastUsedAt"] as? Date ?? plist["lastBootedAt"] as? Date
            )
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-2" → "iOS 18.2".
    static func runtimeName(_ identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last, !last.isEmpty else { return "Unknown runtime" }
        var parts = last.split(separator: "-").map(String.init)
        let os = parts.removeFirst()
        let name = os == "xrOS" ? "visionOS" : os
        return parts.isEmpty ? name : "\(name) \(parts.joined(separator: "."))"
    }

    /// Deletes a simulator through CoreSimulator so its device set stays consistent.
    public static func delete(_ udid: String) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "delete", udid]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
    }
}

public enum AndroidEmulators {
    /// AVDs registered in `home` (normally `~/.android/avd`) whose folder exists and that aren't running.
    public static func list(home: URL) -> [VirtualDevice] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        return names.filter { $0.hasSuffix(".ini") }.sorted().compactMap { name in
            let ini = home.appendingPathComponent(name)
            guard let registration = properties(at: ini) else { return nil }
            let fallback = home.appendingPathComponent((name as NSString).deletingPathExtension + ".avd")
            let folder = registration["path"].map { URL(fileURLWithPath: $0) } ?? fallback
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            // The emulator holds this lock for as long as the AVD runs.
            guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent("hardware-qemu.ini.lock").path) else { return nil }
            let config = properties(at: folder.appendingPathComponent("config.ini")) ?? [:]
            let id = (name as NSString).deletingPathExtension
            let api = registration["target"].map { $0.replacingOccurrences(of: "android-", with: "API ") }
            let used = try? folder.appendingPathComponent("hardware-qemu.ini").resourceValues(forKeys: [.contentModificationDateKey])
            return VirtualDevice(
                id: id, name: config["avd.ini.displayname"] ?? id.replacingOccurrences(of: "_", with: " "),
                platform: [api, config["tag.display"]].compactMap { $0 }.joined(separator: " · "),
                folder: folder, companions: [ini], lastUsed: used?.contentModificationDate
            )
        }
    }

    /// `key=value` lines of an AVD ini file.
    static func properties(at url: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            values[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        return values
    }
}
