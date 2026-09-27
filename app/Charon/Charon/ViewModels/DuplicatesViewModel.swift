// ViewModels/DuplicatesViewModel.swift
// Charon
//
// Runs the duplicate finder over the current scan. Reads files only; removal goes through the Collector.

import CharonKit
import Foundation
import Observation

@MainActor
@Observable
final class DuplicatesViewModel {
    private(set) var groups: [DuplicateGroup] = []
    private(set) var searchedTargetID: String?
    private(set) var progress: Double?
    private(set) var errorMessage: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    var reclaimable: Int64 { groups.reduce(0) { $0 + $1.reclaimable } }
    var isSearching: Bool { progress != nil }

    func search(tree: DiskTree, targetID: String) {
        task?.cancel()
        groups = []
        errorMessage = nil
        progress = 0
        searchedTargetID = targetID
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        Task { [weak self] in
            for await value in stream { self?.progress = value }
        }
        task = Task {
            defer { continuation.finish() }
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try DuplicateFinder().find(in: tree) { continuation.yield($0) }
                }.value
                groups = found
            } catch {
                errorMessage = error.localizedDescription
            }
            progress = nil
        }
    }

    func cancel() {
        task?.cancel()
        progress = nil
    }
}
