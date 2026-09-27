// Offload/OffloadEngine+Recovery.swift
// CharonKit
//
// Brings an interrupted record back to rest. Prefers keeping the original: an offload only rolls forward once
// the symlink is in place (which implies the copy was verified).

import Darwin
import Foundation

public enum RecoveryOutcome: Sendable, Hashable {
    /// Offload undone; the original is where it was.
    case rolledBack
    /// Offload or return finished.
    case completed
    /// Returned to `.offloaded` after an aborted move back.
    case restoredOffloaded
    /// Waiting for the drive to be reconnected to clean up.
    case waitingForDrive
    case failed(String)
}

extension OffloadEngine {

    enum PathState { case directory, symlink, missing, other }

    static func pathState(_ url: URL) -> PathState {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .missing }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    func recover(_ id: UUID) async -> RecoveryOutcome {
        guard let record = record(id) else { return .completed }
        do {
            switch record.phase {
            case .copying, .verifying:
                return try rollBackOffload(record)
            case .swapping:
                return try recoverSwap(record)
            case .cleaning:
                try removeIfPresent(record.hiddenSourceURL)
                return try finishOffload(record)
            case .offloaded:
                return .completed
            case .returnCopying, .returnVerifying:
                try removeIfPresent(record.returnStagingURL)
                return restoreOffloaded(record)
            case .returnSwapping:
                return try recoverReturnSwap(record)
            case .returnCleaning:
                return try finishReturn(record)
            }
        } catch {
            var failed = record
            failed.lastError = error.localizedDescription
            update(failed)
            return .failed(error.localizedDescription)
        }
    }

    private func recoverSwap(_ record: OffloadRecord) throws -> RecoveryOutcome {
        let original = Self.pathState(record.originalURL)
        let hidden = Self.pathState(record.hiddenSourceURL)
        switch (original, hidden) {
        case (.symlink, _):
            // The symlink only goes in after the post-rename recheck, so the copy is good.
            try removeIfPresent(record.hiddenSourceURL)
            return try finishOffload(record)
        case (.missing, .directory):
            // Renamed but never linked: the recheck may not have run, so trust the original.
            try posixCheck(rename(record.hiddenSourceURL.path, record.originalPath))
            return try rollBackOffload(record)
        default:
            return try rollBackOffload(record)
        }
    }

    private func recoverReturnSwap(_ record: OffloadRecord) throws -> RecoveryOutcome {
        let original = Self.pathState(record.originalURL)
        let staging = Self.pathState(record.returnStagingURL)
        switch (original, staging) {
        case (.missing, .directory):
            // Symlink removed, verified staging not yet renamed into place.
            try posixCheck(rename(record.returnStagingURL.path, record.originalPath))
            return try finishReturn(record)
        case (.directory, .missing):
            return try finishReturn(record)
        default:
            try removeIfPresent(record.returnStagingURL)
            return restoreOffloaded(record)
        }
    }

    /// Undo an offload: make sure the original is in place, then drop the partial copy.
    private func rollBackOffload(_ record: OffloadRecord) throws -> RecoveryOutcome {
        if Self.pathState(record.originalURL) == .missing, Self.pathState(record.hiddenSourceURL) == .directory {
            try posixCheck(rename(record.hiddenSourceURL.path, record.originalPath))
        }
        // Something recreated the original path while ours was hidden; never drop the only record of where it is.
        if Self.pathState(record.hiddenSourceURL) != .missing {
            var stuck = record
            let message = "The original is at \(record.hiddenSourceURL.path) because something else now occupies "
                + "\(record.originalPath). Move it back by hand, then forget this entry."
            stuck.lastError = message
            update(stuck)
            return .failed(message)
        }
        guard let mount = volumeResolver.mountPoint(forVolumeUUID: record.drive.volumeUUID) else {
            var waiting = record
            waiting.lastError = "\(record.drive.name) disconnected; its partial copy is removed when it's reconnected."
            update(waiting)
            return .waitingForDrive
        }
        try removeIfPresent(record.containerURL(mountPoint: mount))
        try remove(record)
        return .rolledBack
    }

    private func finishOffload(_ record: OffloadRecord) throws -> RecoveryOutcome {
        var done = record
        done.phase = .offloaded
        done.offloadedAt = done.offloadedAt ?? Date()
        done.lastError = nil
        try commit(done)
        return .completed
    }

    private func finishReturn(_ record: OffloadRecord) throws -> RecoveryOutcome {
        var cleaning = record
        cleaning.phase = .returnCleaning
        guard let mount = volumeResolver.mountPoint(forVolumeUUID: record.drive.volumeUUID) else {
            cleaning.lastError = "Home again. The copy on \(record.drive.name) is removed when it's reconnected."
            try commit(cleaning)
            return .waitingForDrive
        }
        try removeIfPresent(record.containerURL(mountPoint: mount))
        try remove(record)
        return .completed
    }

    private func restoreOffloaded(_ record: OffloadRecord) -> RecoveryOutcome {
        var offloaded = record
        offloaded.phase = .offloaded
        update(offloaded)
        return .restoredOffloaded
    }

    private func removeIfPresent(_ url: URL) throws {
        guard Self.pathState(url) != .missing else { return }
        try Self.removeTree(url)
    }
}
