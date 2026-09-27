// Scanner/AdminScan.swift
// CharonKit
//
// Contract between the app and `charon-scan`, the scanner it runs as root for "Scan as Administrator".
// The tool only reads the disk; it writes nothing but its result and progress files, into a directory the
// requesting user owns, without following symlinks.

import Darwin
import Foundation

public struct AdminScanRequest: Sendable, Hashable {
    public var root: String
    public var displayRoot: String
    /// Directory owned by `ownerUID` where results go.
    public var outputDirectory: String
    public var ownerUID: uid_t
    public var largeFileThreshold: Int64
    public var excludedPaths: [String]

    public init(
        root: String, displayRoot: String, outputDirectory: String, ownerUID: uid_t,
        largeFileThreshold: Int64, excludedPaths: [String]
    ) {
        self.root = root
        self.displayRoot = displayRoot
        self.outputDirectory = outputDirectory
        self.ownerUID = ownerUID
        self.largeFileThreshold = largeFileThreshold
        self.excludedPaths = excludedPaths
    }

    public static let resultName = "result.charonscan"
    public static let progressName = "progress.json"
    public static let cancelName = "cancel"

    public var resultPath: String { outputDirectory + "/" + Self.resultName }
    public var progressPath: String { outputDirectory + "/" + Self.progressName }
    public var cancelPath: String { outputDirectory + "/" + Self.cancelName }

    public var arguments: [String] {
        ["--root", root, "--display", displayRoot, "--output", outputDirectory, "--owner", String(ownerUID),
         "--threshold", String(largeFileThreshold)] + excludedPaths.flatMap { ["--exclude", $0] }
    }

    /// Parses `arguments` (without the executable). Nil on anything unexpected.
    public init?(arguments: [String]) {
        var values: [String: String] = [:]
        var excluded: [String] = []
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard index + 1 < arguments.count, key.hasPrefix("--") else { return nil }
            let value = arguments[index + 1]
            if key == "--exclude" { excluded.append(value) } else { values[key] = value }
            index += 2
        }
        guard let root = values["--root"], root.hasPrefix("/"),
              let display = values["--display"], display.hasPrefix("/"),
              let output = values["--output"], output.hasPrefix("/"), !output.contains("/../"),
              let owner = values["--owner"].flatMap(UInt32.init),
              let threshold = values["--threshold"].flatMap(Int64.init), threshold > 0 else { return nil }
        self.init(root: root, displayRoot: display, outputDirectory: output, ownerUID: owner,
                  largeFileThreshold: threshold, excludedPaths: excluded)
    }
}

public enum AdminScanOutput {
    public enum OutputError: Error { case unsafeDirectory(String), writeFailed(String) }

    /// The directory must be a real directory (not a symlink) owned by `owner` and not writable by others,
    /// so running as root can't be tricked into writing anywhere else.
    public static func validate(directory: String, owner: uid_t) throws {
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == owner,
              info.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw OutputError.unsafeDirectory(directory)
        }
    }

    /// Writes `data` as `name` inside a validated directory, replacing it atomically, owned by `owner`.
    public static func write(_ data: Data, name: String, in directory: String, owner: uid_t) throws {
        try validate(directory: directory, owner: owner)
        let temporary = directory + "/." + name + ".\(getpid())"
        unlink(temporary)
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw OutputError.writeFailed(temporary) }
        let written = data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if result <= 0 { return false }
                offset += result
            }
            return true
        }
        fchown(fd, owner, gid_t(UInt32.max))
        close(fd)
        guard written, rename(temporary, directory + "/" + name) == 0 else {
            unlink(temporary)
            throw OutputError.writeFailed(name)
        }
    }

    public static func progressData(_ progress: ScanProgress) -> Data {
        (try? JSONEncoder().encode(progress)) ?? Data()
    }

    public static func readProgress(_ path: String) -> ScanProgress? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(ScanProgress.self, from: data)
    }
}
