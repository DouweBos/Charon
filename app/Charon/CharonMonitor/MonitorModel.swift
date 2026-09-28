// MonitorModel.swift
// CharonMonitor

import AppKit
import CharonKit
import Observation
import UserNotifications

@MainActor
@Observable
final class MonitorModel: NSObject {
    private(set) var boot: VolumeInfo?
    private(set) var level: LowSpacePolicy.Level = .normal
    private(set) var offloadCount = 0
    private(set) var disconnectedDrives: [String] = []
    /// Biggest growth between Charon's last two scans of the startup disk.
    private(set) var growth: [GrowthItem] = []
    private(set) var growthSince: Date?
    @ObservationIgnored private var archiveStamp: Date?

    @ObservationIgnored private let store = UserDefaults(suiteName: MonitorSettings.suiteName) ?? .standard
    @ObservationIgnored private let catalog = VolumeCatalog()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        store.register(defaults: MonitorSettings.defaults)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        refresh(notify: false)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(notify: true) }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(notify: true) }
            })
        }
    }

    var showsFreeSpace: Bool { store.bool(forKey: MonitorSettings.showFreeSpace) }

    var usedFraction: Double {
        guard let boot, boot.totalBytes > 0 else { return 0 }
        return Double(boot.usedBytes) / Double(boot.totalBytes)
    }

    func refresh(notify: Bool) {
        boot = catalog.bootVolume()
        if let boot {
            let next = MonitorSettings.policy(from: store).level(free: boot.availableBytes, total: boot.totalBytes, previous: level)
            if notify, next > level { notifyLowSpace(next, boot: boot) }
            level = next
        }
        refreshOffloads(notify: notify)
        refreshGrowth()
    }

    /// Reads Charon's scan archives only when they change; the trees are dropped once growth is computed.
    private func refreshGrowth() {
        guard let boot else { return }
        let store = ScanArchiveStore()
        let url = store.url(forVolumeID: boot.id)
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard stamp != archiveStamp else { return }
        archiveStamp = stamp
        let id = boot.id
        Task {
            let result = await Task.detached(priority: .utility) { () -> ([GrowthItem], Date?) in
                guard let current = store.load(volumeID: id), let previous = store.loadPrevious(volumeID: id) else { return ([], nil) }
                let comparison = ScanComparison(previous: previous.tree, current: current.tree, previousDate: previous.scannedAt)
                return (comparison.topGrowth(minimum: 500_000_000, limit: 3), previous.scannedAt)
            }.value
            growth = result.0
            growthSince = result.1
        }
    }

    private func refreshOffloads(notify: Bool) {
        let records = ((try? ManifestStore(url: ManifestStore.defaultURL).load())?.records ?? []).filter { $0.phase == .offloaded }
        offloadCount = records.count
        let disconnected = records.filter { OffloadStatus.resolve($0, resolver: catalog) == .disconnected }
        let drives = Array(Set(disconnected.map(\.drive.name))).sorted()
        if notify, store.bool(forKey: MonitorSettings.notifyDisconnected) {
            for drive in drives where !disconnectedDrives.contains(drive) {
                let count = disconnected.filter { $0.drive.name == drive }.count
                post(title: "\(drive) disconnected",
                     body: "\(count) offloaded \(count == 1 ? "folder is" : "folders are") unavailable until it's connected again.")
            }
            for drive in disconnectedDrives where !drives.contains(drive) {
                post(title: "\(drive) reconnected", body: "Offloaded folders on it are available again.")
            }
        }
        disconnectedDrives = drives
    }

    private func notifyLowSpace(_ level: LowSpacePolicy.Level, boot: VolumeInfo) {
        let free = ByteSize.format(boot.availableBytes)
        switch level {
        case .critical: post(title: "\(boot.name) is almost full", body: "Only \(free) left. Open Charon to free up space.")
        case .low: post(title: "\(boot.name) is running low", body: "\(free) free. Open Charon to see where the space went.")
        case .normal: break
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // The monitor lives at Charon.app/Contents/Library/LoginItems/; prefer that copy over any other install.
    private var charonURL: URL? {
        let embedding = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return embedding.pathExtension == "app"
            ? embedding : NSWorkspace.shared.urlForApplication(withBundleIdentifier: MonitorSettings.appBundleID)
    }

    func openCharon() {
        guard let url = charonURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Opens Charon with the folder selected in its scan, where it can be explored or collected for the Trash.
    func show(_ path: String) {
        guard let app = charonURL else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

extension MonitorModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { openCharon() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
