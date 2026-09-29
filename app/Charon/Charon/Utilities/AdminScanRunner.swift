// Utilities/AdminScanRunner.swift
// Charon
//
// Runs the bundled `charon-scan` once as root through macOS's standard administrator prompt.
// Nothing privileged is installed or left running.

import CharonKit
import Foundation
import Security

enum AdminScanRunner {
    enum RunError: LocalizedError {
        case toolMissing
        case untrustedTool
        case declined
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .toolMissing: "The administrator scanner is missing from Charon's app bundle."
            case .untrustedTool: "The administrator scanner isn't signed by the same developer as Charon, so it won't be run as root."
            case .declined: "Scan as Administrator was cancelled."
            case .failed(let message): "The administrator scan failed: \(message)"
            }
        }
    }

    /// Fresh output directory in Charon's caches, readable only by the current user.
    static func makeOutputDirectory() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("dev.houwert.charon/AdminScans/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    /// Returns once the tool exits. Cancel by creating the request's cancel file; the tool checks it while scanning.
    static func run(_ request: AdminScanRequest) async throws {
        guard let tool = Bundle.main.url(forAuxiliaryExecutable: "charon-scan") else { throw RunError.toolMissing }
        guard isSignedLikeCharon(tool) else { throw RunError.untrustedTool }
        let command = ([tool.path] + request.arguments).map(shellQuoted).joined(separator: " ")
        let script = """
        do shell script "\(appleScriptEscaped(command))" with administrator privileges \
        with prompt "Charon needs administrator access to measure folders owned by macOS and other users. It only reads."
        """
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            let message = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // -128 is AppleScript's "User canceled" for a dismissed password prompt.
            if message.contains("-128") { throw RunError.declined }
            throw RunError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The tool must carry the same team signature as the running app; anything else could be a swapped binary.
    static func isSignedLikeCharon(_ tool: URL) -> Bool {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopySigningInformation(selfStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String else { return false }

        var toolCode: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"charon-scan\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(tool as CFURL, [], &toolCode) == errSecSuccess, let toolCode,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(toolCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
