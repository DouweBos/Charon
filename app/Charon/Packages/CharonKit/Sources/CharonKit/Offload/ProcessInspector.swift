// Offload/ProcessInspector.swift
// CharonKit
//
// Finds processes running from, or holding files open inside, a directory (via libproc). Only sees the
// current user's processes, which is where the risk is.

import Darwin
import Foundation

public struct ProcessUsage: Sendable, Hashable {
    public enum Reason: Sendable, Hashable { case runningFromHere, openFile, workingDirectory }

    public var pid: pid_t
    public var name: String
    public var reason: Reason
}

public protocol ProcessInspecting: Sendable {
    func processes(using path: String) -> [ProcessUsage]
}

public struct ProcessInspector: ProcessInspecting {

    public init() {}

    public func processes(using path: String) -> [ProcessUsage] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        func inside(_ candidate: String) -> Bool { candidate == path || candidate.hasPrefix(prefix) }

        var usages: [ProcessUsage] = []
        for pid in Self.allPIDs() where pid != getpid() {
            let executable = Self.executablePath(pid)
            let name = executable.map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)"
            if let executable, inside(executable) {
                usages.append(ProcessUsage(pid: pid, name: name, reason: .runningFromHere))
            } else if let cwd = Self.workingDirectory(pid), inside(cwd) {
                usages.append(ProcessUsage(pid: pid, name: name, reason: .workingDirectory))
            } else if Self.openFilePaths(pid).contains(where: inside) {
                usages.append(ProcessUsage(pid: pid, name: name, reason: .openFile))
            }
        }
        return usages
    }

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(filled, 0)))).filter { $0 > 0 }
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }

    static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    static func openFilePaths(_ pid: pid_t) -> [String] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / stride)
        let filled = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return [] }

        return fds.prefix(Int(filled) / stride).compactMap { fd in
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return nil }
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { return nil }
            return withUnsafeBytes(of: &info.pvip.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
    }
}
