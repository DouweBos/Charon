// Cleanup/DuplicateFinder.swift
// CharonKit
//
// Finds identical large files in a scan: group by size, then by a hash of the first and last 64 KB, then by a
// full SHA-256. APFS clones of each other are dropped, since removing one frees nothing.

import CryptoKit
import Darwin
import Foundation

public struct DuplicateGroup: Sendable, Hashable, Identifiable {
    public var bytes: Int64
    public var paths: [String]
    public var id: String { paths.joined(separator: "|") }
    /// Space freed by keeping one copy.
    public var reclaimable: Int64 { bytes * Int64(paths.count - 1) }
}

public struct DuplicateFinder: Sendable {
    public var minimumBytes: Int64

    public init(minimumBytes: Int64 = 50_000_000) {
        self.minimumBytes = minimumBytes
    }

    /// Reads file contents; run off the main thread. Paths are real paths from the tree.
    public func find(in tree: DiskTree, progress: @Sendable (Double) -> Void = { _ in }) throws -> [DuplicateGroup] {
        var bySize: [Int64: [String]] = [:]
        for id in 0..<tree.nodeCount {
            let node = DiskTree.NodeID(id)
            guard tree.kind(node) == .file, tree.size(node) >= minimumBytes, tree.isAttached(node) else { continue }
            bySize[Self.logicalSize(tree.realPath(node)) ?? tree.size(node), default: []].append(tree.realPath(node))
        }
        let sizeGroups = bySize.filter { $0.value.count > 1 }
        var groups: [DuplicateGroup] = []
        var done = 0
        for (size, paths) in sizeGroups {
            try Task.checkCancellation()
            for sample in regroup(paths, by: Self.sampleHash) where sample.count > 1 {
                for full in regroup(sample, by: Self.fullHash) where full.count > 1 {
                    let distinct = Self.droppingClones(full)
                    if distinct.count > 1 { groups.append(DuplicateGroup(bytes: size, paths: distinct.sorted())) }
                }
            }
            done += 1
            progress(Double(done) / Double(sizeGroups.count))
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    private func regroup(_ paths: [String], by key: (String) -> Data?) -> [[String]] {
        var buckets: [Data: [String]] = [:]
        for path in paths {
            if let hash = key(path) { buckets[hash, default: []].append(path) }
        }
        return Array(buckets.values)
    }

    static func logicalSize(_ path: String) -> Int64? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Int64(info.st_size)
    }

    static func sampleHash(_ path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let chunk = 64 * 1024
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: chunk) else { return nil }
        hasher.update(data: head)
        if let end = try? handle.seekToEnd(), end > UInt64(chunk) {
            try? handle.seek(toOffset: end - UInt64(chunk))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return Data(hasher.finalize())
    }

    static func fullHash(_ path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return Data(hasher.finalize())
    }

    /// Keeps one path per APFS clone family (ATTR_CMNEXT_CLONEID).
    static func droppingClones(_ paths: [String]) -> [String] {
        var seen = Set<UInt64>()
        return paths.filter { path in
            guard let clone = cloneID(path), clone != 0 else { return true }
            return seen.insert(clone).inserted
        }
    }

    static func cloneID(_ path: String) -> UInt64? {
        var list = attrlist()
        list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        list.commonattr = 0x8000_0000 // ATTR_CMN_RETURNED_ATTRS
        list.forkattr = 0x0000_0100 // ATTR_CMNEXT_CLONEID
        var buffer = [UInt8](repeating: 0, count: 64)
        let result = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &list, raw.baseAddress, raw.count, UInt32(0x20)) // FSOPT_ATTR_CMN_EXTENDED
        }
        guard result == 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            let returned = raw.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
            guard returned.forkattr & 0x100 != 0 else { return nil }
            return raw.loadUnaligned(fromByteOffset: 4 + MemoryLayout<attribute_set_t>.size, as: UInt64.self)
        }
    }
}
