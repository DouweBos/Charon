// Treemap/SquarifiedLayout.swift
// CharonKit
//
// Squarified treemap (Bruls, Huizing, van Wijk 2000): rows are grown while that keeps tiles closer to square.

import CoreGraphics

public enum SquarifiedLayout {

    /// Lays out `weights` in `rect`. Returns one rect per weight, in input order. Zero weights get empty rects.
    public static func layout(weights: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: weights.count)
        let total = weights.reduce(0) { $0 + max($1, 0) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let order = weights.indices.filter { weights[$0] > 0 }.sorted { weights[$0] > weights[$1] }
        var areas = order.map { weights[$0] * scale }
        var indices = order
        var remaining = rect

        while !areas.isEmpty {
            let side = Double(min(remaining.width, remaining.height))
            var rowCount = 1
            var best = worstRatio(areas[0..<1], side: side)
            while rowCount < areas.count {
                let candidate = worstRatio(areas[0...rowCount], side: side)
                if candidate > best { break }
                best = candidate
                rowCount += 1
            }
            remaining = placeRow(areas[0..<rowCount], indices: indices[0..<rowCount], in: remaining, into: &result)
            areas.removeFirst(rowCount)
            indices.removeFirst(rowCount)
        }
        return result
    }

    private static func worstRatio(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard let maxArea = row.max(), let minArea = row.min(), sum > 0, minArea > 0, side > 0 else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * maxArea / sumSquared, sumSquared / (sideSquared * minArea))
    }

    /// Places a row along the shorter side of `rect` and returns what's left.
    private static func placeRow(
        _ row: ArraySlice<Double>, indices: ArraySlice<Int>, in rect: CGRect, into result: inout [CGRect]
    ) -> CGRect {
        let sum = row.reduce(0, +)
        if rect.width >= rect.height {
            let width = CGFloat(sum / Double(rect.height))
            var y = rect.minY
            for (area, index) in zip(row, indices) {
                let height = CGFloat(area) / width
                result[index] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: max(rect.width - width, 0), height: rect.height)
        } else {
            let height = CGFloat(sum / Double(rect.width))
            var x = rect.minX
            for (area, index) in zip(row, indices) {
                let width = CGFloat(area) / height
                result[index] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(rect.height - height, 0))
        }
    }
}
