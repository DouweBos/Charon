// DesignSystem/PillTabBar.swift
// Charon
//
// Top-level tab switcher: the selected tab is a filled pill.

import SwiftUI

struct PillTab<ID: Hashable>: Identifiable {
    var id: ID
    var title: String
    var symbol: String
}

struct PillTabBar<ID: Hashable>: View {
    let tabs: [PillTab<ID>]
    let selection: ID
    let onSelect: (ID) -> Void

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(tabs) { tab in
                let isSelected = tab.id == selection
                Button { onSelect(tab.id) } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                        .foregroundStyle(isSelected ? Theme.pillSelectedText : Theme.textPrimary)
                        .background {
                            if isSelected {
                                Capsule().fill(Theme.pillSelected).matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

#Preview {
    @Previewable @State var selection = "analyze"
    PillTabBar(
        tabs: [
            PillTab(id: "analyze", title: "Analyze", symbol: "waveform.path.ecg"),
            PillTab(id: "ferry", title: "Ferry", symbol: "ferry"),
            PillTab(id: "clean", title: "Clean", symbol: "sparkles")
        ],
        selection: selection
    ) { selection = $0 }
    .padding()
    .background(Theme.background)
}
