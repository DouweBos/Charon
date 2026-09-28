// Utilities/LayoutCache.swift
// Charon
//
// Remembers the last computed layout so hover-driven redraws don't redo it.

import Foundation

@MainActor
final class LayoutCache<Key: Hashable, Value> {
    private var key: Key?
    private var value: Value?

    func value(for key: Key, compute: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let computed = compute()
        self.key = key
        value = computed
        return computed
    }
}
