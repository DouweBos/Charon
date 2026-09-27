// SystemSamplerTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct SystemSamplerTests {
    @Test func producesPlausibleReadings() throws {
        var sampler = SystemSampler()
        _ = sampler.sample()
        let sample = sampler.sample(now: Date().addingTimeInterval(1))
        #expect((0...1).contains(sample.cpuUsage))
        #expect(sample.memoryUsed > 0 && sample.memoryUsed <= sample.memoryTotal)
        #expect(sample.diskTotal > 0 && sample.diskUsed <= sample.diskTotal)
        #expect(sample.networkInPerSecond >= 0)
        if let battery = sample.battery { #expect((0...1).contains(battery.level)) }
    }
}
