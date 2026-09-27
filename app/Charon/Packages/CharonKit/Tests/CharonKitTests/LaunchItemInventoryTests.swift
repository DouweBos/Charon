// LaunchItemInventoryTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct LaunchItemInventoryTests {
    @Test func parsesAgentAndFlagsMissingProgram() throws {
        let plist: [String: Any] = [
            "Label": "com.example.updater",
            "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/updater", "--daemon"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let item = try #require(LaunchItemInventory.parse(
            data, url: URL(fileURLWithPath: "/tmp/com.example.updater.plist"), scope: .user, runningLabels: ["com.example.updater"]
        ))
        #expect(item.label == "com.example.updater")
        #expect(item.runsAtLoad && item.keepsAlive && item.isRunning)
        #expect(item.owningApp == "Example")
        #expect(item.isOrphaned)
    }

    @Test func parsesLaunchctlList() {
        let output = "PID\tStatus\tLabel\n123\t0\tcom.running\n-\t0\tcom.idle\n456\t-9\tcom.other\n"
        #expect(LaunchItemInventory.parseRunningLabels(output) == ["com.running", "com.other"])
    }
}
