// Volumes/APFSInspector.swift
// CharonKit
//
// Explains used space a scan can't see: the sealed system volume, support volumes (VM, Preboot, Recovery),
// purgeable space and snapshots. Reads `diskutil apfs list -plist` and `tmutil`, neither needs root.

import Foundation

public struct APFSVolumeUsage: Sendable, Hashable {
    public var name: String
    public var uuid: String
    public var roles: [String]
    public var bytesInUse: Int64
}

public struct APFSContainerUsage: Sendable, Hashable {
    public var reference: String
    public var capacity: Int64
    public var free: Int64
    public var volumes: [APFSVolumeUsage]

    public var dataVolume: APFSVolumeUsage? { volumes.first { $0.roles.contains("Data") } }
    public var systemVolume: APFSVolumeUsage? { volumes.first { $0.roles.contains("System") } }
}

public struct HiddenSpaceItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case system, support, purgeable, unseen }

    public var kind: Kind
    public var bytes: Int64
    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .system: "macOS"
        case .support: "VM, Preboot & Recovery"
        case .purgeable: "Purgeable"
        case .unseen: "Restricted & snapshot-held"
        }
    }

    public var detail: String {
        switch kind {
        case .system: "The sealed, read-only system volume."
        case .support: "Swap files, boot support and recovery volumes."
        case .purgeable: "Local snapshots and caches macOS frees automatically when space runs low."
        case .unseen: "Folders Charon can't read, and blocks still held by snapshots after files were deleted."
        }
    }
}

public enum APFSInspector {

    public static func parse(plist data: Data) throws -> [APFSContainerUsage] {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let containers = root["Containers"] as? [[String: Any]] else { return [] }
        return containers.map { container in
            let volumes = (container["Volumes"] as? [[String: Any]] ?? []).map { volume in
                APFSVolumeUsage(
                    name: volume["Name"] as? String ?? "",
                    uuid: volume["APFSVolumeUUID"] as? String ?? "",
                    roles: volume["Roles"] as? [String] ?? [],
                    bytesInUse: int64(volume["CapacityInUse"])
                )
            }
            return APFSContainerUsage(
                reference: container["ContainerReference"] as? String ?? "",
                capacity: int64(container["CapacityCeiling"]),
                free: int64(container["CapacityFree"]),
                volumes: volumes
            )
        }
    }

    /// The container holding the Data volume with this UUID, or the first container with a Data role.
    public static func bootContainer(in containers: [APFSContainerUsage], dataVolumeUUID: String?) -> APFSContainerUsage? {
        if let dataVolumeUUID, let match = containers.first(where: { $0.volumes.contains { $0.uuid == dataVolumeUUID } }) {
            return match
        }
        return containers.first { $0.dataVolume != nil && $0.systemVolume != nil }
    }

    /// Splits the boot container's used space that isn't in `scannedBytes`.
    public static func breakdown(container: APFSContainerUsage, scannedBytes: Int64, purgeableBytes: Int64) -> [HiddenSpaceItem] {
        let system = container.systemVolume?.bytesInUse ?? 0
        let support = container.volumes
            .filter { !$0.roles.contains("Data") && !$0.roles.contains("System") }
            .reduce(Int64(0)) { $0 + $1.bytesInUse }
        let dataHidden = max((container.dataVolume?.bytesInUse ?? 0) - scannedBytes, 0)
        let purgeable = min(max(purgeableBytes, 0), dataHidden)
        return [
            HiddenSpaceItem(kind: .system, bytes: system),
            HiddenSpaceItem(kind: .support, bytes: support),
            HiddenSpaceItem(kind: .purgeable, bytes: purgeable),
            HiddenSpaceItem(kind: .unseen, bytes: dataHidden - purgeable)
        ].filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    public static func containers() async throws -> [APFSContainerUsage] {
        try parse(plist: try await run("/usr/sbin/diskutil", ["apfs", "list", "-plist"]))
    }

    /// Names of local Time Machine snapshots on `/`.
    public static func localSnapshots() async -> [String] {
        guard let data = try? await run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }
        return (String(bytes: data, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
    }

    private static func int64(_ value: Any?) -> Int64 {
        (value as? NSNumber)?.int64Value ?? 0
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            // Read before waiting so a full pipe can't deadlock the child.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            continuation.resume(returning: data)
        }
    }
}
