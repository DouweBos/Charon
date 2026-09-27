// DesignSystem/UsageBar.swift
// Charon
//
// Thin capacity bar with an optional "X / Y used" caption.

import CharonKit
import SwiftUI

struct UsageBar: View {
    let used: Int64
    let total: Int64
    var showsCaption = true
    var width: CGFloat = 130

    private var fraction: Double {
        total > 0 ? min(Double(used) / Double(total), 1) : 0
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Capsule()
                .fill(Theme.track)
                .frame(width: width, height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.accent).frame(width: width * fraction, height: 5)
                }
            if showsCaption {
                Text("\(ByteSize.format(used)) / \(ByteSize.format(total)) used")
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ByteSize.format(used)) of \(ByteSize.format(total)) used")
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 16) {
        UsageBar(used: 278_660_000_000, total: 512_000_000_000)
        UsageBar(used: 10, total: 100, showsCaption: false)
        UsageBar(used: 100, total: 100)
    }
    .padding()
    .background(Theme.background)
}
