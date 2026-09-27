// ViewModels/StatsViewModel.swift
// Charon
//
// Samples system stats once a second while visible and keeps a short history for sparklines.

import CharonKit
import Foundation
import Observation

@MainActor
@Observable
final class StatsViewModel {
    static let historyLength = 40

    private(set) var latest: SystemSample?
    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var disk: [Double] = []
    private(set) var battery: [Double] = []
    private(set) var networkRates: [Double] = []

    @ObservationIgnored private var sampler = SystemSampler()
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Network has no natural ceiling, so it's scaled to the busiest moment in view.
    var network: [Double] {
        let peak = max(networkRates.max() ?? 1, 1)
        return networkRates.map { $0 / peak }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.takeSample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func takeSample() {
        let sample = sampler.sample()
        latest = sample
        append(sample.cpuUsage, to: &cpu)
        append(sample.memoryTotal > 0 ? Double(sample.memoryUsed) / Double(sample.memoryTotal) : 0, to: &memory)
        append(sample.diskTotal > 0 ? Double(sample.diskUsed) / Double(sample.diskTotal) : 0, to: &disk)
        if let level = sample.battery?.level { append(level, to: &battery) }
        append(sample.networkInPerSecond + sample.networkOutPerSecond, to: &networkRates)
    }

    private func append(_ value: Double, to series: inout [Double]) {
        series = Array((series + [value]).suffix(Self.historyLength))
    }
}
