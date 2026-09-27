// DesignSystem/ProgressStrip.swift
// Charon
//
// Labeled linear progress with an optional cancel button, for scans and ferries.

import SwiftUI

struct ProgressStrip: View {
    let title: String
    let detail: String
    /// Nil shows an indeterminate bar.
    var fraction: Double?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(detail).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                if let onCancel {
                    Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Cancel")
                }
            }
            if let fraction {
                ProgressView(value: fraction).tint(Theme.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Theme.accent)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressStrip(title: "Ferrying Movies", detail: "12.4 GB of 42 GB", fraction: 0.3, onCancel: {})
        ProgressStrip(title: "Scanning", detail: "1,203,442 files")
    }
    .frame(width: 420)
    .padding()
    .background(Theme.surface)
}
