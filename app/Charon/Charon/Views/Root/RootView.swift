// Views/Root/RootView.swift
// Charon
//
// Window shell: top tab bar and the selected tab's content.

import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(FerryViewModel.self) private var ferry

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch navigator.tab {
                case .analyze: AnalyzeView()
                case .ferry: FerryView()
                case .clean, .uninstall, .optimize: ComingSoonView(tab: navigator.tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.textPrimary)
        .frame(minWidth: 960, minHeight: 640)
        .sheet(item: Binding(get: { ferry.request }, set: { if $0 == nil { ferry.dismissRequest() } })) { _ in
            FerrySheet()
        }
        .sheet(item: Binding(get: { navigator.sheet }, set: { if $0 == nil { navigator.dismissSheet() } })) { sheet in
            switch sheet {
            case .fullDiskAccess: FullDiskAccessSheet()
            case .restrictedFolders: RestrictedFoldersSheet()
            }
        }
        .alert("Charon", isPresented: Binding(get: { ferry.errorMessage != nil }, set: { if !$0 { ferry.dismissError() } })) {
            Button("OK") { ferry.dismissError() }
        } message: {
            Text(ferry.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckFullDiskAccess()
            Task { await ferry.refresh() }
        }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Spacer()
            PillTabBar(
                tabs: AppTab.allCases.map { PillTab(id: $0, title: $0.title, symbol: $0.symbol) },
                selection: navigator.tab
            ) { navigator.selectTab($0) }
            Spacer()
            Menu {
                Button("Rescan", systemImage: "arrow.clockwise") { model.rescanCurrent() }
                Button("Full Disk Access…", systemImage: "lock.shield") { SystemIntegration.openFullDiskAccessSettings() }
                Divider()
                Button("Settings…", systemImage: "gearshape") { openSettings() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 32, height: 28)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }
}

struct ComingSoonView: View {
    let tab: AppTab

    var body: some View {
        ContentUnavailableView(
            tab.title, systemImage: tab.symbol,
            description: Text("Not built yet. Analyze and Ferry are where Charon does its work for now.")
        )
        .foregroundStyle(Theme.textSecondary)
    }
}
