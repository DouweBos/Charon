// APFSInspectorTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct APFSInspectorTests {
    private let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict><key>Containers</key><array>
      <dict><key>ContainerReference</key><string>disk1</string><key>CapacityCeiling</key><integer>500</integer>
        <key>CapacityFree</key><integer>400</integer><key>Volumes</key><array>
        <dict><key>Name</key><string>iSCPreboot</string><key>APFSVolumeUUID</key><string>P</string>
          <key>Roles</key><array><string>Preboot</string></array><key>CapacityInUse</key><integer>100</integer></dict>
      </array></dict>
      <dict><key>ContainerReference</key><string>disk3</string><key>CapacityCeiling</key><integer>1000</integer>
        <key>CapacityFree</key><integer>100</integer><key>Volumes</key><array>
        <dict><key>Name</key><string>Macintosh HD</string><key>APFSVolumeUUID</key><string>S</string>
          <key>Roles</key><array><string>System</string></array><key>CapacityInUse</key><integer>120</integer></dict>
        <dict><key>Name</key><string>Data</string><key>APFSVolumeUUID</key><string>D</string>
          <key>Roles</key><array><string>Data</string></array><key>CapacityInUse</key><integer>700</integer></dict>
        <dict><key>Name</key><string>VM</string><key>APFSVolumeUUID</key><string>V</string>
          <key>Roles</key><array><string>VM</string></array><key>CapacityInUse</key><integer>80</integer></dict>
      </array></dict>
    </array></dict></plist>
    """

    @Test func parsesContainersAndPicksBoot() throws {
        let containers = try APFSInspector.parse(plist: Data(plist.utf8))
        #expect(containers.count == 2)
        let boot = try #require(APFSInspector.bootContainer(in: containers, dataVolumeUUID: "D"))
        #expect(boot.reference == "disk3")
        #expect(boot.systemVolume?.bytesInUse == 120)
        #expect(APFSInspector.bootContainer(in: containers, dataVolumeUUID: nil)?.reference == "disk3")
    }

    @Test func breakdownSplitsHiddenSpace() throws {
        let boot = try #require(APFSInspector.parse(plist: Data(plist.utf8)).last)
        let items = APFSInspector.breakdown(container: boot, scannedBytes: 600, purgeableBytes: 30)
        let bytes = Dictionary(uniqueKeysWithValues: items.map { ($0.kind, $0.bytes) })
        #expect(bytes[.system] == 120)
        #expect(bytes[.support] == 80)
        #expect(bytes[.purgeable] == 30)
        #expect(bytes[.unseen] == 70)
    }
}
