// Scanner/ScanArchive.swift
// CharonKit
//
// Compact binary snapshot of a finished scan so relaunching shows the last result instantly.
// Layout: magic, JSON header, then raw column arrays; children are rebuilt from parents.

import Foundation

public struct ScanArchive: Sendable {
    public struct Header: Codable, Sendable, Hashable {
        public var version: Int
        public var rootPath: String
        public var displayRootPath: String
        public var scannedAt: Date
        public var progress: ScanProgress
        public var nodeCount: Int
    }

    public var tree: DiskTree
    public var progress: ScanProgress
    public var scannedAt: Date

    public init(tree: DiskTree, progress: ScanProgress, scannedAt: Date) {
        self.tree = tree
        self.progress = progress
        self.scannedAt = scannedAt
    }

    static let magic = Data("CHRNSCAN".utf8)
    static let version = 1

    public enum ArchiveError: Error { case badMagic, unsupportedVersion, truncated }

    // MARK: - Encoding

    public func encoded() throws -> Data {
        let count = tree.nodeCount
        let header = Header(
            version: Self.version, rootPath: tree.rootPath, displayRootPath: tree.displayRootPath,
            scannedAt: scannedAt, progress: progress, nodeCount: count
        )
        let headerData = try JSONEncoder().encode(header)

        var data = Self.magic
        data.appendInteger(UInt32(headerData.count))
        data.append(headerData)
        data.appendColumn(tree.parents)
        data.appendColumn(tree.sizes)
        data.appendColumn(tree.privateSizes)
        data.appendColumn(tree.itemCounts)
        data.appendColumn(tree.kinds.map(\.rawValue))
        let names = Data(tree.names.joined(separator: "\u{0}").utf8)
        data.appendInteger(UInt64(names.count))
        data.append(names)
        return data
    }

    // MARK: - Decoding

    public static func decode(_ data: Data) throws -> ScanArchive {
        var reader = DataReader(data: data)
        guard try reader.bytes(magic.count) == magic else { throw ArchiveError.badMagic }
        let headerLength = Int(try reader.integer(UInt32.self))
        let header = try JSONDecoder().decode(Header.self, from: try reader.bytes(headerLength))
        guard header.version == version else { throw ArchiveError.unsupportedVersion }

        let count = header.nodeCount
        let parents: [Int32] = try reader.column(count)
        let sizes: [Int64] = try reader.column(count)
        let privateSizes: [Int64] = try reader.column(count)
        let itemCounts: [Int64] = try reader.column(count)
        let kindValues: [UInt8] = try reader.column(count)
        let namesLength = Int(try reader.integer(UInt64.self))
        let nameData = try reader.bytes(namesLength)
        guard let joined = String(bytes: nameData, encoding: .utf8) else { throw ArchiveError.truncated }
        let names = joined
            .split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        guard names.count == count else { throw ArchiveError.truncated }

        var childLists = [[DiskTree.NodeID]](repeating: [], count: count)
        for (index, parent) in parents.enumerated() where parent >= 0 {
            childLists[Int(parent)].append(DiskTree.NodeID(index))
        }
        let tree = DiskTree(
            rootPath: header.rootPath, displayRootPath: header.displayRootPath, names: names, parents: parents,
            childLists: childLists, sizes: sizes, privateSizes: privateSizes, itemCounts: itemCounts,
            kinds: kindValues.map { DiskTree.Kind(rawValue: $0) ?? .file }
        )
        return ScanArchive(tree: tree, progress: header.progress, scannedAt: header.scannedAt)
    }
}

/// Where archives live: one file per volume in the user's caches.
public struct ScanArchiveStore: Sendable {
    public let directory: URL

    public init(directory: URL = ScanArchiveStore.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("com.houwert.Charon/Scans")
    }

    public func url(forVolumeID id: String) -> URL {
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".charonscan")
    }

    public func save(_ archive: ScanArchive, volumeID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try archive.encoded().write(to: url(forVolumeID: volumeID), options: .atomic)
    }

    public func load(volumeID: String) -> ScanArchive? {
        guard let data = try? Data(contentsOf: url(forVolumeID: volumeID), options: .mappedIfSafe) else { return nil }
        return try? ScanArchive.decode(data)
    }
}

// MARK: - Binary helpers

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendColumn<T: FixedWidthInteger>(_ values: [T]) {
        values.withUnsafeBufferPointer { buffer in
            append(UnsafeBufferPointer(start: UnsafeRawPointer(buffer.baseAddress)?.assumingMemoryBound(to: UInt8.self),
                                       count: buffer.count * MemoryLayout<T>.stride))
        }
    }
}

private struct DataReader {
    let data: Data
    var offset = 0

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw ScanArchive.ArchiveError.truncated }
        defer { offset += count }
        return data.subdata(in: data.startIndex + offset..<data.startIndex + offset + count)
    }

    mutating func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let raw = try bytes(MemoryLayout<T>.size)
        return T(littleEndian: raw.withUnsafeBytes { $0.loadUnaligned(as: T.self) })
    }

    /// Columns are written in native (little-endian on Apple silicon and Intel) layout.
    mutating func column<T: FixedWidthInteger>(_ count: Int) throws -> [T] {
        let raw = try bytes(count * MemoryLayout<T>.stride)
        return raw.withUnsafeBytes { buffer in
            (0..<count).map { buffer.loadUnaligned(fromByteOffset: $0 * MemoryLayout<T>.stride, as: T.self) }
        }
    }
}
