// CharonMonitorApp.swift
// CharonMonitor
//
// Menu bar login item: shows free space, warns when it runs low, and when a drive holding offloaded
// folders disconnects.

import SwiftUI

@main
struct CharonMonitorApp: App {
    @State private var monitor = MonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MonitorMenu()
                .environment(monitor)
        } label: {
            MonitorLabel()
                .environment(monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
