// main.swift
// charon-scan
//
// Read-only disk scanner that Charon runs as root for "Scan as Administrator". Writes only its progress and
// result into the requesting user's output directory, and stops when a "cancel" file appears there.

import CharonKit
import Foundation

guard let request = AdminScanRequest(arguments: Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data("usage: charon-scan --root <path> --display <path> --output <dir> --owner <uid> --threshold <bytes>\n".utf8))
    exit(64)
}

do {
    try AdminScanOutput.validate(directory: request.outputDirectory, owner: request.ownerUID)
} catch {
    FileHandle.standardError.write(Data("charon-scan: unsafe output directory\n".utf8))
    exit(73)
}

// The boot disk is scanned through the Data volume, so match both spellings of each excluded path.
var options = ScanOptions(largeFileThreshold: request.largeFileThreshold)
options.excludedPaths = Set(request.excludedPaths + request.excludedPaths.map { "/System/Volumes/Data" + $0 })

var last: ScanUpdate?
do {
    for try await update in DiskScanner(options: options).scan(root: URL(fileURLWithPath: request.root), displayRootPath: request.displayRoot) {
        last = update
        try? AdminScanOutput.write(
            AdminScanOutput.progressData(update.progress), name: AdminScanRequest.progressName,
            in: request.outputDirectory, owner: request.ownerUID
        )
        if FileManager.default.fileExists(atPath: request.cancelPath) { exit(130) }
    }
} catch {
    FileHandle.standardError.write(Data("charon-scan: \(error.localizedDescription)\n".utf8))
    exit(74)
}

guard let last else { exit(74) }
do {
    let archive = ScanArchive(tree: last.tree, progress: last.progress, scannedAt: Date())
    try AdminScanOutput.write(archive.encoded(), name: AdminScanRequest.resultName, in: request.outputDirectory, owner: request.ownerUID)
} catch {
    FileHandle.standardError.write(Data("charon-scan: couldn't write result\n".utf8))
    exit(73)
}
