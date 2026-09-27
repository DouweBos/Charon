// Scanner/BulkDirectoryReader.swift
// CharonKit
//
// Reads a directory's entries and their size attributes with getattrlistbulk(2): one syscall per batch
// instead of a stat per file.

import Darwin
import Foundation

struct DirectoryEntry {
    enum EntryType { case file, directory, symlink, other }

    var name: String
    var type: EntryType
    var device: Int32
    var flags: UInt32
    var fileID: UInt64
    var linkCount: UInt32
    var allocatedSize: Int64
    var privateSize: Int64?
}

/// One reader per worker thread; owns a reusable buffer.
final class BulkDirectoryReader {

    // Values from <sys/attr.h>; declared here so they stay UInt32 regardless of how the macros import.
    private enum Attr {
        static let cmnName: UInt32 = 0x0000_0001
        static let cmnDevID: UInt32 = 0x0000_0002
        static let cmnObjType: UInt32 = 0x0000_0008
        static let cmnFlags: UInt32 = 0x0004_0000
        static let cmnFileID: UInt32 = 0x0200_0000
        static let cmnError: UInt32 = 0x2000_0000
        static let cmnReturnedAttrs: UInt32 = 0x8000_0000
        static let fileLinkCount: UInt32 = 0x0000_0001
        static let fileAllocSize: UInt32 = 0x0000_0004
        static let cmnExtPrivateSize: UInt32 = 0x0000_0008
        static let optionCommonExtended: UInt64 = 0x0000_0020
    }

    private let bufferSize = 256 * 1024
    private let buffer: UnsafeMutableRawPointer
    private let measurePrivateSize: Bool

    init(measurePrivateSize: Bool) {
        self.measurePrivateSize = measurePrivateSize
        buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
    }

    deinit { buffer.deallocate() }

    /// Calls `body` for each entry. Throws the POSIX error if the directory can't be opened or read.
    func read(path: String, _ body: (DirectoryEntry) -> Void) throws {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError.current }
        defer { close(fd) }

        var list = attrlist()
        list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        list.commonattr = Attr.cmnReturnedAttrs | Attr.cmnName | Attr.cmnError | Attr.cmnDevID
            | Attr.cmnObjType | Attr.cmnFlags | Attr.cmnFileID
        list.fileattr = Attr.fileLinkCount | Attr.fileAllocSize
        var options: UInt64 = 0
        if measurePrivateSize {
            list.forkattr = Attr.cmnExtPrivateSize
            options |= Attr.optionCommonExtended
        }

        while true {
            let count = getattrlistbulk(fd, &list, buffer, bufferSize, options)
            if count == 0 { return }
            if count < 0 { throw POSIXError.current }
            var entryStart = buffer
            for _ in 0..<count {
                let length = Int(entryStart.loadUnaligned(as: UInt32.self))
                if let entry = parse(entryStart) { body(entry) }
                entryStart += length
            }
        }
    }

    // Attributes are packed in a fixed order and only present when returned, hence one branch each.
    // swiftlint:disable:next cyclomatic_complexity
    private func parse(_ start: UnsafeMutableRawPointer) -> DirectoryEntry? {
        var field = start + MemoryLayout<UInt32>.size
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        if returned.commonattr & Attr.cmnError != 0 {
            let error = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
            if error != 0 { return nil }
        }

        var name = ""
        if returned.commonattr & Attr.cmnName != 0 {
            let reference = field.loadUnaligned(as: attrreference_t.self)
            let namePointer = (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
            name = String(cString: namePointer)
            field += MemoryLayout<attrreference_t>.size
        }

        var device: Int32 = 0
        if returned.commonattr & Attr.cmnDevID != 0 {
            device = field.loadUnaligned(as: Int32.self)
            field += MemoryLayout<Int32>.size
        }

        var type = DirectoryEntry.EntryType.other
        if returned.commonattr & Attr.cmnObjType != 0 {
            switch field.loadUnaligned(as: UInt32.self) {
            case UInt32(VREG.rawValue): type = .file
            case UInt32(VDIR.rawValue): type = .directory
            case UInt32(VLNK.rawValue): type = .symlink
            default: type = .other
            }
            field += MemoryLayout<UInt32>.size
        }

        var flags: UInt32 = 0
        if returned.commonattr & Attr.cmnFlags != 0 {
            flags = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }

        var fileID: UInt64 = 0
        if returned.commonattr & Attr.cmnFileID != 0 {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }

        var linkCount: UInt32 = 1
        if returned.fileattr & Attr.fileLinkCount != 0 {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }

        var allocated: Int64 = 0
        if returned.fileattr & Attr.fileAllocSize != 0 {
            allocated = field.loadUnaligned(as: Int64.self)
            field += MemoryLayout<Int64>.size
        }

        var privateSize: Int64?
        if returned.forkattr & Attr.cmnExtPrivateSize != 0 {
            privateSize = field.loadUnaligned(as: Int64.self)
        }

        guard !name.isEmpty else { return nil }
        return DirectoryEntry(
            name: name, type: type, device: device, flags: flags, fileID: fileID,
            linkCount: linkCount, allocatedSize: allocated, privateSize: privateSize
        )
    }
}
