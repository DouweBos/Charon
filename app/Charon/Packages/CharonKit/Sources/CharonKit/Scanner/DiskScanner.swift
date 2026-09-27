// Scanner/DiskScanner.swift
// CharonKit
//
// Concurrent, single-volume directory walker that streams consistent partial trees while it runs.

import Darwin
import Foundation
import Synchronization

public struct ScanOptions: Sendable, Hashable {
    /// Files at least this big become their own treemap tile; smaller ones roll into their folder.
    public var largeFileThreshold: Int64
    /// Measure bytes not shared with APFS clones. Roughly doubles scan time, and local snapshots make it read low.
    public var measurePrivateSize: Bool
    public var workerCount: Int
    public var snapshotInterval: Duration
    /// Real paths of directories to skip entirely.
    public var excludedPaths: Set<String> = []

    public init(
        largeFileThreshold: Int64 = 50_000_000,
        measurePrivateSize: Bool = false,
        workerCount: Int = max(ProcessInfo.processInfo.activeProcessorCount, 4),
        snapshotInterval: Duration = .milliseconds(250)
    ) {
        self.largeFileThreshold = largeFileThreshold
        self.measurePrivateSize = measurePrivateSize
        self.workerCount = workerCount
        self.snapshotInterval = snapshotInterval
    }
}

public struct ScanProgress: Sendable, Hashable, Codable {
    public var filesScanned: Int64 = 0
    public var directoriesScanned: Int64 = 0
    public var bytesScanned: Int64 = 0
    /// Directories we couldn't read, usually for lack of Full Disk Access.
    public var unreadableDirectories: Int64 = 0
    /// The first few unreadable directories (real paths), so the UI can show what's missing.
    public var unreadablePaths: [String] = []
    public var elapsed: Duration = .zero
    public var isComplete = false

    public init() {}
}

public struct ScanUpdate: Sendable {
    public var tree: DiskTree
    public var progress: ScanProgress

    public init(tree: DiskTree, progress: ScanProgress) {
        self.tree = tree
        self.progress = progress
    }
}

public struct DiskScanner: Sendable {
    public var options: ScanOptions

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
    }

    /// Streams snapshots every `snapshotInterval`, ending with one where `progress.isComplete` is true.
    /// Cancelling the consuming task stops the workers.
    public func scan(root: URL, displayRootPath: String? = nil) -> AsyncThrowingStream<ScanUpdate, Error> {
        let options = options
        return AsyncThrowingStream { continuation in
            var info = stat()
            guard lstat(root.path, &info) == 0 else {
                continuation.finish(throwing: POSIXError.current)
                return
            }
            let job = ScanJob(
                rootPath: root.path, displayRootPath: displayRootPath ?? root.path,
                device: Int32(info.st_dev), options: options
            )
            let clock = ContinuousClock()
            let start = clock.now

            let ticker = Task.detached {
                while !Task.isCancelled, !job.isFinished {
                    try? await Task.sleep(for: options.snapshotInterval)
                    guard !job.isFinished else { break }
                    continuation.yield(job.snapshot(elapsed: clock.now - start, complete: false))
                }
            }

            job.run {
                ticker.cancel()
                if job.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.yield(job.snapshot(elapsed: clock.now - start, complete: true))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                job.cancel()
                ticker.cancel()
            }
        }
    }
}

// MARK: - ScanJob

/// Shared state for one scan. The tree is guarded by a mutex and only touched once per finished directory.
final class ScanJob: @unchecked Sendable {
    private struct State {
        var tree: DiskTree
        var progress = ScanProgress()
    }

    private let state: Mutex<State>
    private let seenHardlinks = Mutex<Set<UInt64>>([])
    private let queue = WorkQueue<(DiskTree.NodeID, String)>()
    private let rootPath: String
    private let device: Int32
    private let options: ScanOptions
    private let finished = Atomic<Bool>(false)

    private static let unreadablePathLimit = 500

    // Flags from <sys/stat.h>.
    private static let datalessFlag: UInt32 = 0x4000_0000

    init(rootPath: String, displayRootPath: String, device: Int32, options: ScanOptions) {
        self.rootPath = rootPath
        self.device = device
        self.options = options
        state = Mutex(State(tree: DiskTree(rootPath: rootPath, displayRootPath: displayRootPath)))
    }

    var isFinished: Bool { finished.load(ordering: .acquiring) }
    var isCancelled: Bool { queue.isCancelled }

    func cancel() { queue.cancel() }

    func snapshot(elapsed: Duration, complete: Bool) -> ScanUpdate {
        state.withLock { state in
            var progress = state.progress
            progress.elapsed = elapsed
            progress.isComplete = complete
            return ScanUpdate(tree: state.tree, progress: progress)
        }
    }

    /// Spawns worker threads; `completion` runs on the last worker to exit.
    func run(completion: @escaping @Sendable () -> Void) {
        queue.push([(DiskTree.root, rootPath)])
        let remaining = Atomic<Int>(options.workerCount)
        for index in 0..<options.workerCount {
            let thread = Thread { [self] in
                disableDatalessMaterialization()
                let reader = BulkDirectoryReader(measurePrivateSize: options.measurePrivateSize)
                while let (node, path) = queue.pop() {
                    scanDirectory(node: node, path: path, reader: reader)
                    queue.finishItem()
                }
                if remaining.subtract(1, ordering: .acquiringAndReleasing).newValue == 0 {
                    finished.store(true, ordering: .releasing)
                    completion()
                }
            }
            thread.name = "Charon scanner \(index)"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private func scanDirectory(node: DiskTree.NodeID, path: String, reader: BulkDirectoryReader) {
        var looseBytes: Int64 = 0
        var loosePrivate: Int64 = 0
        var fileCount: Int64 = 0
        var subdirectories: [String] = []
        var largeFiles: [LargeFile] = []
        let prefix = path.hasSuffix("/") ? path : path + "/"

        do {
            try reader.read(path: path) { entry in
                switch entry.type {
                case .directory:
                    // Other devices are mount points (external disks, the system volume); dataless dirs would download.
                    guard entry.device == device, entry.flags & Self.datalessFlag == 0 else { return }
                    guard options.excludedPaths.isEmpty || !options.excludedPaths.contains(prefix + entry.name) else { return }
                    subdirectories.append(entry.name)
                case .file, .symlink, .other:
                    if entry.linkCount > 1, entry.type == .file, !firstSighting(of: entry.fileID) { return }
                    let privateSize = entry.privateSize ?? entry.allocatedSize
                    fileCount += 1
                    if entry.type == .file, entry.allocatedSize >= options.largeFileThreshold {
                        largeFiles.append(LargeFile(name: entry.name, size: entry.allocatedSize, privateSize: privateSize))
                    }
                    looseBytes += entry.allocatedSize
                    loosePrivate += privateSize
                }
            }
        } catch {
            state.withLock { state in
                state.progress.unreadableDirectories += 1
                if state.progress.unreadablePaths.count < Self.unreadablePathLimit {
                    state.progress.unreadablePaths.append(path)
                }
            }
        }

        let jobs: [(DiskTree.NodeID, String)] = state.withLock { state in
            for file in largeFiles {
                _ = state.tree.addNode(name: file.name, parent: node, kind: .file, size: file.size, privateSize: file.privateSize)
            }
            state.tree.accumulate(into: node, size: looseBytes, privateSize: loosePrivate, items: fileCount)
            state.progress.filesScanned += fileCount
            state.progress.directoriesScanned += 1
            state.progress.bytesScanned += looseBytes
            return subdirectories.map { name in
                let child = state.tree.addNode(name: name, parent: node, kind: .directory)
                state.tree.accumulate(into: child, size: 0, privateSize: 0, items: 1)
                return (child, prefix + name)
            }
        }
        queue.push(jobs)
    }

    private struct LargeFile {
        var name: String
        var size: Int64
        var privateSize: Int64
    }

    private func firstSighting(of fileID: UInt64) -> Bool {
        seenHardlinks.withLock { $0.insert(fileID).inserted }
    }

    private func disableDatalessMaterialization() {
        // IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF
        _ = setiopolicy_np(3, 1, 1)
    }
}
