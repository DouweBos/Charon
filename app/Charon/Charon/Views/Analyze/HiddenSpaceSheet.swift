// Views/Analyze/HiddenSpaceSheet.swift
// Charon

import CharonKit
import SwiftUI

struct HiddenSpaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator

    private var hidden: HiddenSpaceViewModel { model.hiddenSpace }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("System & other").font(.system(size: 18, weight: .semibold))
            Text("Used space that isn't in any folder Charon can read.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)

            if hidden.isLoading {
                ProgressStrip(title: "Reading APFS volumes…", detail: "")
            } else if let message = hidden.errorMessage {
                Banner(symbol: "xmark.octagon", message: message, tone: .negative)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(hidden.items) { item in
                        row(item)
                    }
                }
                if !hidden.snapshots.isEmpty {
                    Label("\(hidden.snapshots.count) local Time Machine snapshots. macOS deletes them after 24 hours or when space runs low.",
                          systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") { navigator.dismissSheet() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 540, height: 440)
        .background(Theme.background)
        .onAppear {
            model.hiddenSpace.load(scannedBytes: model.scannedBytes, purgeableBytes: model.currentVolume?.purgeableBytes ?? 0)
        }
    }

    private func row(_ item: HiddenSpaceItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: symbol(item.kind)).foregroundStyle(Theme.treemapNeutral).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .medium))
                Text(item.kind == .purgeable ? item.detail + " Already counted as free." : item.detail)
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(ByteSize.format(item.bytes)).font(.system(size: 14, weight: .medium, design: .monospaced))
        }
        .card(padding: Theme.Spacing.md)
    }

    private func symbol(_ kind: HiddenSpaceItem.Kind) -> String {
        switch kind {
        case .system: "apple.logo"
        case .support: "memorychip"
        case .purgeable: "arrow.3.trianglepath"
        case .unseen: "eye.slash"
        }
    }
}
