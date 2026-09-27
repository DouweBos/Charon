// ViewModels/HiddenSpaceViewModel.swift
// Charon
//
// Explains "System & other": what macOS keeps on volumes and in places the scan can't see.

import CharonKit
import Foundation
import Observation

@MainActor
@Observable
final class HiddenSpaceViewModel {
    private(set) var items: [HiddenSpaceItem] = []
    private(set) var snapshots: [String] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(scannedBytes: Int64, purgeableBytes: Int64) {
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let containers = try await APFSInspector.containers()
                let dataURL = URL(fileURLWithPath: "/System/Volumes/Data")
                let dataUUID = try? dataURL.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
                guard let boot = APFSInspector.bootContainer(in: containers, dataVolumeUUID: dataUUID) else {
                    errorMessage = "Couldn't find the startup disk's APFS container."
                    return
                }
                items = APFSInspector.breakdown(container: boot, scannedBytes: scannedBytes, purgeableBytes: purgeableBytes)
                snapshots = await APFSInspector.localSnapshots()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
