// DesignSystem/StaticCanvas.swift
// Charon
//
// A Canvas that only redraws when its key changes, so expensive drawing isn't repeated on unrelated
// view updates like pointer hover.

import SwiftUI

struct StaticCanvas<Key: Hashable>: View, Equatable {
    let key: Key
    let draw: (inout GraphicsContext) -> Void

    var body: some View {
        Canvas { context, _ in draw(&context) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }
}

#Preview {
    StaticCanvas(key: 1) { context in
        context.fill(Path(ellipseIn: CGRect(x: 20, y: 20, width: 120, height: 120)), with: .color(Theme.accent))
    }
    .frame(width: 160, height: 160)
    .background(Theme.background)
}
