// SquarifiedLayoutTests.swift
// CharonKitTests

import CoreGraphics
import Testing
@testable import CharonKit

struct SquarifiedLayoutTests {
    private let rect = CGRect(x: 0, y: 0, width: 600, height: 400)

    @Test func areasAreProportionalAndFillTheRect() {
        let weights: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = SquarifiedLayout.layout(weights: weights, in: rect)
        let total = weights.reduce(0, +)
        for (weight, tile) in zip(weights, rects) {
            let expected = Double(rect.width * rect.height) * weight / total
            #expect(abs(Double(tile.width * tile.height) - expected) < 0.5)
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(tile))
        }
    }

    @Test func tilesDoNotOverlap() {
        let rects = SquarifiedLayout.layout(weights: [50, 20, 10, 10, 5, 3, 1, 1], in: rect)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func keepsInputOrderAndSkipsZeroWeights() {
        let rects = SquarifiedLayout.layout(weights: [1, 0, 9], in: rect)
        #expect(rects[1] == .zero)
        #expect(rects[2].width * rects[2].height > rects[0].width * rects[0].height)
    }

    @Test func tilesAreReasonablySquare() {
        let rects = SquarifiedLayout.layout(weights: Array(repeating: 1, count: 24), in: rect)
        for tile in rects {
            #expect(max(tile.width / tile.height, tile.height / tile.width) < 3)
        }
    }
}
