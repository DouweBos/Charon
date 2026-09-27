// Views/Settings/SettingsView.swift
// Charon
//
// Preferences window. Every setting here is documented in docs/settings.md.

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.largeFileThresholdMB) private var largeFileThresholdMB = 50
    @AppStorage(AppSettings.measurePrivateSize) private var measurePrivateSize = false
    @AppStorage(AppSettings.rememberScans) private var rememberScans = true
    @AppStorage(AppSettings.treemapDepth) private var treemapDepth = 2
    @AppStorage(AppSettings.showStats) private var showStats = true
    @AppStorage(AppSettings.driveFolder) private var driveFolder = "Charon"

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
            Section("Treemap") {
                Picker("Nesting depth", selection: $treemapDepth) {
                    Text("1 level").tag(1)
                    Text("2 levels").tag(2)
                    Text("3 levels").tag(3)
                }
                Toggle("Show live stats", isOn: $showStats)
            }
            Section("Offload") {
                TextField("Folder on the external drive", text: $driveFolder)
                Text("New offloads go to this folder at the root of the drive. Takes effect after relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
