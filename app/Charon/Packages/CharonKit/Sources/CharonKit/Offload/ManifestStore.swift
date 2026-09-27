// Offload/ManifestStore.swift
// CharonKit
//
// Plist-backed list of offload records. The local manifest is the source of truth; each drive gets a
// best-effort mirror so a drive describes what's on it.

import Foundation

public struct OffloadManifest: Codable, Sendable, Hashable {
    public var records: [OffloadRecord] = []

    public init(records: [OffloadRecord] = []) {
        self.records = records
    }
}

public struct ManifestStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Charon/manifest.plist`
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Charon/manifest.plist")
    }

    public func load() throws -> OffloadManifest {
        guard FileManager.default.fileExists(atPath: url.path) else { return OffloadManifest() }
        return try PropertyListDecoder().decode(OffloadManifest.self, from: Data(contentsOf: url))
    }

    public func save(_ manifest: OffloadManifest) throws {
        try Self.write(manifest, to: url)
    }

    static func write(_ manifest: OffloadManifest, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }
}
