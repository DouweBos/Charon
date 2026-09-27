// Offload/OffloadError.swift
// CharonKit

import Foundation

public enum OffloadError: LocalizedError, Equatable {
    case sourceMissing(String)
    case sourceNotADirectory(String)
    case driveUnavailable(String)
    case notEnoughSpace(needed: Int64, available: Int64)
    case verificationFailed(path: String, reason: String)
    case changedDuringOffload(String)
    case brokenLink(String)
    case recordNotFound
    case recordBusy
    case blocked([String])
    case keptDriveCopy(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "\(path) no longer exists."
        case .sourceNotADirectory(let path):
            return "\(path) is not a directory."
        case .driveUnavailable(let name):
            return "\(name) isn't connected."
        case .notEnoughSpace(let needed, let available):
            return "Needs \(ByteSize.format(needed)) but only \(ByteSize.format(available)) is free."
        case .verificationFailed(let path, let reason):
            return "Verification failed at \(path): \(reason). Nothing was removed."
        case .changedDuringOffload(let path):
            return "\(path) changed while it was being offloaded. Nothing was removed; try again once it's idle."
        case .brokenLink(let reason):
            return reason
        case .recordNotFound:
            return "That offload record no longer exists."
        case .recordBusy:
            return "That directory is already being moved."
        case .blocked(let reasons):
            return reasons.joined(separator: "\n")
        case .keptDriveCopy(let message):
            return message
        case .cancelled:
            return "Cancelled. Nothing was removed."
        }
    }
}

enum CopyReadError: Error {
    case unreadable(String, String)
}

/// Set from a cancellation handler, polled by blocking file work.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func check() throws {
        if isCancelled { throw OffloadError.cancelled }
    }
}

/// Runs blocking filesystem work on its own thread so it never parks a Swift concurrency thread.
func runBlocking<T: Sendable>(_ work: @escaping @Sendable (CancellationFlag) throws -> T) async throws -> T {
    let flag = CancellationFlag()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result { try work(flag) })
            }
        }
    } onCancel: {
        flag.cancel()
    }
}
