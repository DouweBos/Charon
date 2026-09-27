// LowSpacePolicyTests.swift
// CharonKitTests

import Testing
@testable import CharonKit

struct LowSpacePolicyTests {
    private let policy = LowSpacePolicy(lowBytes: 20, lowFraction: 0.1, criticalBytes: 5, recoveryMargin: 2)

    @Test func thresholdsUseTheLargerOfBytesAndFraction() {
        #expect(policy.level(free: 25, total: 100, previous: .normal) == .normal)
        #expect(policy.level(free: 25, total: 400, previous: .normal) == .low)
        #expect(policy.level(free: 4, total: 100, previous: .normal) == .critical)
    }

    @Test func hysteresisKeepsLevelsUntilRecovered() {
        #expect(policy.level(free: 21, total: 100, previous: .low) == .low)
        #expect(policy.level(free: 23, total: 100, previous: .low) == .normal)
        #expect(policy.level(free: 6, total: 100, previous: .critical) == .critical)
        #expect(policy.level(free: 8, total: 100, previous: .critical) == .low)
    }
}
