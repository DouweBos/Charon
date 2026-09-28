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

    static let sampleBytes = 64 * 1024

    static func sampleHash(_ path: String) -> Data? {
        withFile(path) { fd, buffer in
            var hasher = SHA256()
            guard let head = readChunk(fd, buffer, sampleBytes) else { return nil }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: head))
            let end = lseek(fd, 0, SEEK_END)
            if end > sampleBytes, lseek(fd, end - off_t(sampleBytes), SEEK_SET) >= 0,
               let tail = readChunk(fd, buffer, sampleBytes) {
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: tail))
            }
            return Data(hasher.finalize())
        }
    }

    static func fullHash(_ path: String) -> Data? {
        withFile(path) { fd, buffer in
            var hasher = SHA256()
            while true {
                guard !Task.isCancelled, let count = readChunk(fd, buffer, chunkSize) else { return nil }
                if count == 0 { break }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
            }
            return Data(hasher.finalize())
        }
    }

    private static let chunkSize = 1 << 20

    /// POSIX reads into one reused buffer: FileHandle hands back autoreleased Data that a worker thread never
    /// drains, so hashing gigabytes kept every chunk alive. F_NOCACHE keeps the scan from flooding the page cache.
    private static func withFile(_ path: String, _ body: (Int32, UnsafeMutableRawPointer) -> Data?) -> Data? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        return body(fd, buffer)
    }

    private static func readChunk(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int? {
        let result = read(fd, buffer, count)
        return result < 0 ? nil : result
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
