// Ferry/TreeVerifier.swift
// CharonKit
//
// Proves a copy matches its source: same entries, types, sizes, symlink targets, and SHA-256 of every file.

import CryptoKit
import Darwin
import Foundation

struct TreeVerifier {
    let flag: CancellationFlag
    let progress: @Sendable (Int64) -> Void

    private static let chunkSize = 1 << 20

    /// Returns a digest over every file's relative path and content hash.
    func verify(source: URL, copy: URL) throws -> String {
        var tree = SHA256()
        var bytes: Int64 = 0
        try compare(source.path, copy.path, relative: "", tree: &tree, bytes: &bytes)
        return tree.finalize().hexString
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func compare(_ source: String, _ copy: String, relative: String, tree: inout SHA256, bytes: inout Int64) throws {
        try flag.check()
        var sourceInfo = stat()
        var copyInfo = stat()
        try posixCheck(lstat(source, &sourceInfo))
        guard lstat(copy, &copyInfo) == 0 else { throw mismatch(relative, "missing from the copy") }

        let type = sourceInfo.st_mode & S_IFMT
        guard type == copyInfo.st_mode & S_IFMT else { throw mismatch(relative, "different file type") }

        switch type {
        case S_IFDIR:
            let sourceNames = try Self.entries(source)
            let copyNames = try Self.entries(copy)
            guard sourceNames == copyNames else { throw mismatch(relative, "different directory contents") }
            for name in sourceNames {
                try compare(source + "/" + name, copy + "/" + name, relative: relative + "/" + name, tree: &tree, bytes: &bytes)
            }
        case S_IFLNK:
            guard try Self.linkTarget(source) == Self.linkTarget(copy) else { throw mismatch(relative, "different link target") }
        case S_IFREG:
            guard sourceInfo.st_size == copyInfo.st_size else { throw mismatch(relative, "different size") }
            let sourceDigest = try hash(source, bypassCache: false, bytes: &bytes)
            let copyDigest = try hash(copy, bypassCache: true, bytes: &bytes)
            guard sourceDigest == copyDigest else { throw mismatch(relative, "contents differ") }
            tree.update(data: Data((relative + "\u{0}").utf8))
            tree.update(data: sourceDigest)
        default:
            break
        }
    }

    /// Hashes a file. The copy is read with F_NOCACHE so we verify what's on the disk, not what's still in RAM.
    private func hash(_ path: String, bypassCache: Bool, bytes: inout Int64) throws -> Data {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError.current }
        defer { close(fd) }
        if bypassCache { _ = fcntl(fd, F_NOCACHE, 1) }

        var hasher = SHA256()
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            try flag.check()
            let count = read(fd, buffer, Self.chunkSize)
            if count < 0 { throw POSIXError.current }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
            bytes += Int64(count)
            progress(bytes / 2)
        }
        return Data(hasher.finalize())
    }

    private func mismatch(_ relative: String, _ reason: String) -> FerryError {
        .verificationFailed(path: relative.isEmpty ? "/" : relative, reason: reason)
    }

    /// Directory entries that the copier copies (special files are skipped on both sides).
    static func entries(_ path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path).filter { name in
            var info = stat()
            guard lstat(path + "/" + name, &info) == 0 else { return false }
            let type = info.st_mode & S_IFMT
            return type == S_IFDIR || type == S_IFREG || type == S_IFLNK
        }.sorted()
    }

    static func linkTarget(_ path: String) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: path)
    }
}

/// Cheap metadata digest (paths, types, sizes, mtimes). Taken after verification and again after the
/// source is renamed, to catch writes that slipped in between.
enum TreeFingerprint {
    static func capture(_ url: URL) throws -> String {
        var hasher = SHA256()
        try visit(url.path, relative: "", into: &hasher)
        return hasher.finalize().hexString
    }

    private static func visit(_ path: String, relative: String, into hasher: inout SHA256) throws {
        var info = stat()
        try posixCheck(lstat(path, &info))
        let type = info.st_mode & S_IFMT
        // The root's own timestamps change when it's renamed; only its contents matter.
        let mtime = relative.isEmpty ? timespec() : info.st_mtimespec
        hasher.update(data: Data("\(relative)|\(type)|\(info.st_size)|\(mtime.tv_sec).\(mtime.tv_nsec)\n".utf8))
        if type == S_IFDIR {
            for name in try TreeVerifier.entries(path) {
                try visit(path + "/" + name, relative: relative + "/" + name, into: &hasher)
            }
        }
    }
}

extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
