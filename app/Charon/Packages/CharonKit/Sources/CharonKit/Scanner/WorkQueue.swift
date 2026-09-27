// Scanner/WorkQueue.swift
// CharonKit
//
// Blocking LIFO queue for worker threads. LIFO keeps the frontier (and memory) small on deep trees.

import Foundation

final class WorkQueue<Item>: @unchecked Sendable {
    private let condition = NSCondition()
    private var items: [Item] = []
    private var active = 0
    private var cancelled = false

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    func push(_ newItems: [Item]) {
        guard !newItems.isEmpty else { return }
        condition.lock()
        items.append(contentsOf: newItems)
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks until there's work, or returns nil once the queue is drained and no worker can add more.
    func pop() -> Item? {
        condition.lock()
        defer { condition.unlock() }
        while items.isEmpty, active > 0, !cancelled {
            condition.wait()
        }
        guard !cancelled, let item = items.popLast() else {
            condition.broadcast()
            return nil
        }
        active += 1
        return item
    }

    /// Call after processing a popped item (and pushing its children).
    func finishItem() {
        condition.lock()
        active -= 1
        if active == 0, items.isEmpty { condition.broadcast() }
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        cancelled = true
        items.removeAll()
        condition.broadcast()
        condition.unlock()
    }
}
