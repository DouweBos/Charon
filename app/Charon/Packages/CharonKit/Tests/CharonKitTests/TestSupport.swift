// TestSupport.swift
// CharonKitTests

import Foundation

/// Temporary directory removed on deinit.
final class TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("charon-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ relative: String, bytes: Int, seed: UInt8 = 7) throws -> URL {
        let target = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for index in 0..<bytes { data[index] = UInt8(truncatingIfNeeded: index &* 31 &+ Int(seed)) }
        try data.write(to: target)
        return target
    }

    @discardableResult
    func directory(_ relative: String) throws -> URL {
        let target = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }
}
