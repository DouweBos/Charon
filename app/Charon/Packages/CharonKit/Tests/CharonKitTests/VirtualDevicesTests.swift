// VirtualDevicesTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct VirtualDevicesTests {
    @Test func namesRuntimes() {
        #expect(SimulatorDevices.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-18-2") == "iOS 18.2")
        #expect(SimulatorDevices.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-2-0") == "visionOS 2.0")
        #expect(SimulatorDevices.runtimeName("") == "Unknown runtime")
    }

    @Test func listsShutDownSimulatorsOnly() throws {
        let root = try TempDirectory()
        try simulator(in: root, udid: "AAAA", name: "iPhone 16", state: 1)
        try simulator(in: root, udid: "BBBB", name: "iPad Pro", state: 3)
        try root.file("device_set.plist", bytes: 10)

        let devices = SimulatorDevices.list(root: root.url)
        #expect(devices.map(\.id) == ["AAAA"])
        #expect(devices.first?.name == "iPhone 16")
        #expect(devices.first?.platform == "iOS 18.2")
    }

    @Test func listsIdleEmulatorsWithTheirIni() throws {
        let home = try TempDirectory()
        try emulator(in: home, id: "Pixel_9", display: "Pixel 9")
        try emulator(in: home, id: "Running", display: "Running")
        try home.file("Running.avd/hardware-qemu.ini.lock", bytes: 1)
        try "path=\(home.url.path)/Gone.avd\ntarget=android-34\n".write(
            to: home.url.appendingPathComponent("Gone.ini"), atomically: true, encoding: .utf8
        )

        let devices = AndroidEmulators.list(home: home.url)
        #expect(devices.map(\.id) == ["Pixel_9"])
        #expect(devices.first?.name == "Pixel 9")
        #expect(devices.first?.platform == "API 35 · Google Play")
        #expect(devices.first?.companions.map(\.lastPathComponent) == ["Pixel_9.ini"])
    }

    @Test func measuresDevicesWithTitles() async throws {
        let home = try TempDirectory()
        let avd = try home.directory(".android/avd")
        try "path=\(avd.path)/Pixel_9.avd\ntarget=android-35\n".write(
            to: avd.appendingPathComponent("Pixel_9.ini"), atomically: true, encoding: .utf8
        )
        try home.file(".android/avd/Pixel_9.avd/userdata.img", bytes: 200_000)
        let measurer = CleanMeasurer(resolver: CleanResolver(homeDirectory: home.url))
        let category = try #require(CleanCatalog.all.first { $0.id == "android.emulators" })

        let items = try await measurer.measure(category)
        #expect(items.map(\.title) == ["Pixel 9"])
        #expect(items.first?.companions.count == 1)
        #expect((items.first?.bytes ?? 0) >= 200_000)
    }

    private func simulator(in root: TempDirectory, udid: String, name: String, state: Int) throws {
        let plist: [String: Any] = [
            "UDID": udid, "name": name, "state": state, "isDeleted": false,
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-18-2"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try root.directory(udid)
        try data.write(to: root.url.appendingPathComponent("\(udid)/device.plist"))
    }

    private func emulator(in home: TempDirectory, id: String, display: String) throws {
        let folder = try home.directory("\(id).avd")
        try "path=\(folder.path)\ntarget=android-35\n".write(
            to: home.url.appendingPathComponent("\(id).ini"), atomically: true, encoding: .utf8
        )
        try "avd.ini.displayname = \(display)\ntag.display = Google Play\n".write(
            to: folder.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8
        )
    }
}
