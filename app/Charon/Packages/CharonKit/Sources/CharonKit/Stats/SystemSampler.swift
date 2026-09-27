// Stats/SystemSampler.swift
// CharonKit
//
// Live CPU, memory, disk, battery and network readings. Rates are deltas between consecutive samples.

import Darwin
import Foundation
import IOKit.ps

public struct BatteryReading: Sendable, Hashable {
    public var level: Double
    public var isCharging: Bool
    public var isOnPower: Bool
    /// Nil while macOS is still estimating.
    public var minutesRemaining: Int?
}

public struct SystemSample: Sendable, Hashable {
    public var date: Date
    /// 0...1 across all cores.
    public var cpuUsage: Double
    public var loadAverage: Double
    public var memoryUsed: Int64
    public var memoryTotal: Int64
    public var diskUsed: Int64
    public var diskTotal: Int64
    public var battery: BatteryReading?
    public var networkInPerSecond: Double
    public var networkOutPerSecond: Double
}

public struct SystemSampler {
    private var previousTicks: (busy: UInt64, total: UInt64)?
    private struct NetworkReading {
        var bytesIn: UInt64
        var bytesOut: UInt64
        var date: Date
    }

    private var previousNetwork: NetworkReading?

    public init() {}

    public mutating func sample(now: Date = Date()) -> SystemSample {
        let disk = VolumeCatalog().bootVolume()
        let (bytesIn, bytesOut) = Self.networkBytes()
        var rateIn = 0.0
        var rateOut = 0.0
        if let previous = previousNetwork {
            let seconds = max(now.timeIntervalSince(previous.date), 0.001)
            rateIn = Double(bytesIn &- previous.bytesIn) / seconds
            rateOut = Double(bytesOut &- previous.bytesOut) / seconds
        }
        previousNetwork = NetworkReading(bytesIn: bytesIn, bytesOut: bytesOut, date: now)

        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)

        return SystemSample(
            date: now,
            cpuUsage: cpuUsage(),
            loadAverage: load[0],
            memoryUsed: Self.memoryUsed(),
            memoryTotal: Int64(ProcessInfo.processInfo.physicalMemory),
            diskUsed: disk?.usedBytes ?? 0,
            diskTotal: disk?.totalBytes ?? 0,
            battery: Self.battery(),
            networkInPerSecond: rateIn,
            networkOutPerSecond: rateOut
        )
    }

    private mutating func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { previousTicks = (busy, total) }
        guard let previous = previousTicks, total > previous.total else { return 0 }
        return Double(busy - previous.busy) / Double(total - previous.total)
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    static func memoryUsed() -> Int64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = Int64(getpagesize())
        let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        return (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * pageSize
    }

    static func networkBytes() -> (UInt64, UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let data = entry.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            bytesIn += UInt64(stats.ifi_ibytes)
            bytesOut += UInt64(stats.ifi_obytes)
        }
        return (bytesIn, bytesOut)
    }

    static func battery() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let minutes = description[kIOPSTimeToEmptyKey] as? Int
            return BatteryReading(
                level: Double(current) / Double(maximum),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isOnPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil
            )
        }
        return nil
    }
}
