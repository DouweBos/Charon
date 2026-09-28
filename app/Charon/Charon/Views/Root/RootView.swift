// Views/Root/RootView.swift
// Charon
//
// Window shell: top tab bar and the selected tab's content.

import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(OffloadViewModel.self) private var offload

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch navigator.tab {
                case .analyze: AnalyzeView()
                case .offload: OffloadView()
                case .clean: CleanView()
                case .uninstall: UninstallView()
                case .optimize: OptimizeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.textPrimary)
        .frame(minWidth: 960, minHeight: 640)
        .sheet(item: Binding(get: { offload.request }, set: { if $0 == nil { offload.dismissRequest() } })) { _ in
            OffloadSheet()
        }
        .sheet(item: Binding(get: { navigator.sheet }, set: { if $0 == nil { navigator.dismissSheet() } })) { sheet in
            switch sheet {
            case .fullDiskAccess: FullDiskAccessSheet()
            case .restrictedFolders: RestrictedFoldersSheet()
            case .hiddenSpace: HiddenSpaceSheet()
            }
        }
        .alert("Charon", isPresented: Binding(get: { offload.alertMessage != nil }, set: { if !$0 { offload.dismissAlert() } })) {
            Button("OK") { offload.dismissAlert() }
        } message: {
            Text(offload.alertMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckFullDiskAccess()
            Task { await offload.refresh() }
        }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            PillTabBar(
                tabs: AppTab.allCases.map { PillTab(id: $0, title: $0.title, symbol: $0.symbol) },
                selection: navigator.tab
            ) { navigator.selectTab($0) }
            HStack {
                HistoryButtons(
                    canGoBack: model.canGoBack, canGoForward: navigator.canGoForward,
                    onBack: { model.goBack() }, onForward: { model.goForward() }
                )
                Spacer()
                moreMenu
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    private var moreMenu: some View {
        Menu {
            Button("Rescan", systemImage: "arrow.clockwise") { model.rescanCurrent() }
            Button("Scan as Administrator…", systemImage: "lock.open") { model.rescanCurrentAsAdministrator() }
            Button("Export Current Folder as CSV…", systemImage: "square.and.arrow.up") { model.exportCurrentFolder() }
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
}
