// Views/Settings/SettingsView.swift
// Charon
//
// Preferences window. Every setting here is documented in docs/settings.md.

import CharonKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.largeFileThresholdMB) private var largeFileThresholdMB = 50
    @AppStorage(AppSettings.measurePrivateSize) private var measurePrivateSize = false
    @AppStorage(AppSettings.rememberScans) private var rememberScans = true
    @AppStorage(AppSettings.treemapDepth) private var treemapDepth = 3
    @AppStorage(AppSettings.driveFolder) private var driveFolder = "Charon"
    @AppStorage(AppSettings.deletePermanently) private var deletePermanently = false
    @AppStorage(MonitorSettings.lowGigabytes) private var lowGigabytes = 20
    @AppStorage(MonitorSettings.lowPercent) private var lowPercent = 5
    @AppStorage(MonitorSettings.criticalGigabytes) private var criticalGigabytes = 5
    @AppStorage(MonitorSettings.showFreeSpace) private var showFreeSpace = true
    @AppStorage(MonitorSettings.notifyDisconnected) private var notifyDisconnected = true
    @State private var monitorEnabled = MonitorLoginItem.isEnabled
    @State private var monitorError: String?

    var body: some View {
        Form {
            Section("Scanning") {
                Picker("Show files as their own tile from", selection: $largeFileThresholdMB) {
                    ForEach([10, 50, 100, 500, 1000], id: \.self) { Text("\($0) MB").tag($0) }
                }
                Toggle("Open on the last scan", isOn: $rememberScans)
                Toggle("Measure APFS clone savings", isOn: $measurePrivateSize)
                Text("Counts only bytes not shared with clones. Slower, and local Time Machine snapshots make it read low.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Skipped folders") {
                if model.excludedPaths.isEmpty {
                    Text("None. Right-click a folder in Analyze and choose Skip in Future Scans.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.excludedPaths, id: \.self) { path in
                    HStack {
                        Text(path).font(.monoCaption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { model.removeExclusion(path) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Stop skipping \(path)")
                    }
                }
                Button("Add Folder…") { model.chooseExclusion() }
            }
            Section("Treemap") {
                Picker("Nesting depth", selection: $treemapDepth) {
                    Text("1 level").tag(1)
                    Text("2 levels").tag(2)
                    Text("3 levels").tag(3)
                    Text("4 levels").tag(4)
                }
            }
            Section("Removing") {
                Toggle("Delete immediately instead of moving to the Trash", isOn: $deletePermanently)
                Text("Applies to the Collector, Clean and Uninstall. Deleted items can't be recovered.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Offload") {
                TextField("Folder on the external drive", text: $driveFolder)
                Text("New offloads go to this folder at the root of the drive. Takes effect after relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu Bar Monitor") {
                Toggle("Show the monitor in the menu bar at login", isOn: Binding(
                    get: { monitorEnabled },
                    set: { setMonitor($0) }
                ))
                if MonitorLoginItem.needsApproval {
                    Button("Allow in Login Items…") { MonitorLoginItem.openLoginItemsSettings() }
                }
                if let monitorError {
                    Text(monitorError).font(.caption).foregroundStyle(Theme.danger)
                }
                Stepper("Warn below \(lowGigabytes) GB free", value: $lowGigabytes, in: 5...200, step: 5)
                Stepper("or below \(lowPercent)% of the disk", value: $lowPercent, in: 1...30)
                Stepper("Critical below \(criticalGigabytes) GB", value: $criticalGigabytes, in: 1...50)
                Toggle("Show free space next to the icon", isOn: $showFreeSpace)
                Toggle("Notify when a drive with offloaded folders disconnects", isOn: $notifyDisconnected)
            }
            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    Text(model.hasFullDiskAccess ? "Granted" : "Not granted")
                        .foregroundStyle(model.hasFullDiskAccess ? Theme.success : Theme.warning)
                }
                Button("Open Privacy Settings…") { SystemIntegration.openFullDiskAccessSettings() }
            }
        }
        .formStyle(.grouped)
        .onAppear { monitorEnabled = MonitorLoginItem.isEnabled }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setMonitor(_ enabled: Bool) {
        do {
            try MonitorLoginItem.setEnabled(enabled)
            monitorError = nil
        } catch {
            monitorError = error.localizedDescription
        }
        monitorEnabled = MonitorLoginItem.isEnabled
    }
}
