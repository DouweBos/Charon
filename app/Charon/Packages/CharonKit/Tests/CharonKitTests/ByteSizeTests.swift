// ByteSizeTests.swift
// CharonKitTests

import Testing
@testable import CharonKit

struct ByteSizeTests {
    @Test func formatsDecimalUnits() {
        #expect(ByteSize.format(0) == "0 bytes")
        #expect(ByteSize.format(999) == "999 bytes")
        #expect(ByteSize.format(12_345) == "12 KB")
        #expect(ByteSize.format(512_000_000) == "512 MB")
        #expect(ByteSize.format(226_390_000_000) == "226.39 GB")
        #expect(ByteSize.format(2_000_000_000_000) == "2.00 TB")
    }

    @Test func capacities() {
        #expect(ByteSize.capacity(494_380_000_000) == "494 GB")
        #expect(ByteSize.capacity(2_000_000_000_000) == "2.0 TB")
    }

    @Test func percentages() {
        #expect(ByteSize.percent(72, of: 100) == "72%")
        #expect(ByteSize.percent(1, of: 1000) == "<1%")
        #expect(ByteSize.percent(5, of: 0) == "0%")
    }
}
