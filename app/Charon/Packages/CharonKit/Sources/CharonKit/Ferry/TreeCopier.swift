// Ferry/TreeCopier.swift
// CharonKit
//
// Recursive copy via copyfile(3): data, xattrs, ACLs, modes and times; symlinks copied as links.

import Darwin
import Foundation

struct TreeCopier {
    let flag: CancellationFlag
    let progress: @Sendable (Int64) -> Void
    /// Called after each file; tests use it to simulate crashes and unplugged drives.
    var afterFile: (Int) throws -> Void = { _ in }

    private final class Counter {
        var bytes: Int64 = 0
        var files = 0
        var base: Int64 = 0
        var flag: CancellationFlag
        var progress: @Sendable (Int64) -> Void

        init(flag: CancellationFlag, progress: @escaping @Sendable (Int64) -> Void) {
            self.flag = flag
            self.progress = progress
        }
    }

    func copy(from source: URL, to destination: URL) throws {
        let counter = Counter(flag: flag, progress: progress)
        try copyItem(source.path, destination.path, counter)
    }

    private func copyItem(_ source: String, _ destination: String, _ counter: Counter) throws {
        try flag.check()
        var info = stat()
        try posixCheck(lstat(source, &info))

        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            try posixCheck(mkdir(destination, 0o700))
            for name in try FileManager.default.contentsOfDirectory(atPath: source).sorted() {
                try copyItem(source + "/" + name, destination + "/" + name, counter)
            }
            // Metadata last so the directory's mtime and (possibly read-only) mode survive writing its children.
            try copyFile(source, destination, flags: copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW), counter)
        case S_IFREG, S_IFLNK:
            try copyFile(source, destination, flags: copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_EXCL), counter)
            counter.base += Int64(info.st_size)
            counter.bytes = counter.base
            counter.progress(counter.bytes)
            counter.files += 1
            try afterFile(counter.files)
        default:
            // Sockets, FIFOs and device nodes are runtime artifacts; the verifier skips them too.
            return
        }
    }

    private func copyFile(_ source: String, _ destination: String, flags: copyfile_flags_t, _ counter: Counter) throws {
        guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
        defer { copyfile_state_free(state) }

        let callback: copyfile_callback_t = { what, stage, state, _, _, context in
            guard let context else { return COPYFILE_CONTINUE }
            let counter = Unmanaged<Counter>.fromOpaque(context).takeUnretainedValue()
            if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                counter.progress(counter.base + Int64(copied))
            }
            return counter.flag.isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
        }
        let context = Unmanaged.passUnretained(counter).toOpaque()
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), context)

        let result = withExtendedLifetime(counter) { copyfile(source, destination, state, flags) }
        if result != 0 {
            try flag.check()
            throw POSIXError.current
        }
    }
}
