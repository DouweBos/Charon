// Ferry/Ferryman+Recovery.swift
// CharonKit
//
// Brings an interrupted record back to rest. Prefers keeping the original: a ferry only rolls forward once
// the symlink is in place (which implies the copy was verified).

import Darwin
import Foundation

public enum RecoveryOutcome: Sendable, Hashable {
    /// Ferry undone; the original is where it was.
    case rolledBack
    /// Ferry or return finished.
    case completed
    /// Returned to `.ferried` after an aborted bring-home.
    case restoredFerried
    /// Waiting for the shore to be reconnected to clean up.
    case waitingForShore
    case failed(String)
}

extension Ferryman {

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
                return try rollBackFerry(record)
            case .swapping:
                return try recoverSwap(record)
            case .cleaning:
                try removeIfPresent(record.hiddenSourceURL)
                return try finishFerry(record)
            case .ferried:
                return .completed
            case .returnCopying, .returnVerifying:
                try removeIfPresent(record.returnStagingURL)
                return restoreFerried(record)
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

    private func recoverSwap(_ record: FerryRecord) throws -> RecoveryOutcome {
        let original = Self.pathState(record.originalURL)
        let hidden = Self.pathState(record.hiddenSourceURL)
        switch (original, hidden) {
        case (.symlink, _):
            // The symlink only goes in after the post-rename recheck, so the copy is good.
            try removeIfPresent(record.hiddenSourceURL)
            return try finishFerry(record)
        case (.missing, .directory):
            // Renamed but never linked: the recheck may not have run, so trust the original.
            try posixCheck(rename(record.hiddenSourceURL.path, record.originalPath))
            return try rollBackFerry(record)
        default:
            return try rollBackFerry(record)
        }
    }

    private func recoverReturnSwap(_ record: FerryRecord) throws -> RecoveryOutcome {
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
            return restoreFerried(record)
        }
    }

    /// Undo a ferry: make sure the original is in place, then drop the partial copy.
    private func rollBackFerry(_ record: FerryRecord) throws -> RecoveryOutcome {
        if Self.pathState(record.originalURL) == .missing, Self.pathState(record.hiddenSourceURL) == .directory {
            try posixCheck(rename(record.hiddenSourceURL.path, record.originalPath))
        }
        guard let mount = volumeResolver.mountPoint(forVolumeUUID: record.shore.volumeUUID) else {
            var waiting = record
            waiting.lastError = "\(record.shore.name) disconnected; its partial copy is removed when it's reconnected."
            update(waiting)
            return .waitingForShore
        }
        try removeIfPresent(record.containerURL(mountPoint: mount))
        try remove(record)
        return .rolledBack
    }

    private func finishFerry(_ record: FerryRecord) throws -> RecoveryOutcome {
        var done = record
        done.phase = .ferried
        done.ferriedAt = done.ferriedAt ?? Date()
        done.lastError = nil
        try commit(done)
        return .completed
    }

    private func finishReturn(_ record: FerryRecord) throws -> RecoveryOutcome {
        var cleaning = record
        cleaning.phase = .returnCleaning
        guard let mount = volumeResolver.mountPoint(forVolumeUUID: record.shore.volumeUUID) else {
            cleaning.lastError = "Home again. The copy on \(record.shore.name) is removed when it's reconnected."
            try commit(cleaning)
            return .waitingForShore
        }
        try removeIfPresent(record.containerURL(mountPoint: mount))
        try remove(record)
        return .completed
    }

    private func restoreFerried(_ record: FerryRecord) -> RecoveryOutcome {
        var ferried = record
        ferried.phase = .ferried
        update(ferried)
        return .restoredFerried
    }

    private func removeIfPresent(_ url: URL) throws {
        guard Self.pathState(url) != .missing else { return }
        try FileManager.default.removeItem(at: url)
    }
}
