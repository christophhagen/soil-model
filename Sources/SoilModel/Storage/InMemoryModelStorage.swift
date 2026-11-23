import Foundation
import Soil

/**
 A simple model storage that keeps all samples in memory.

 The storage keeps the full history of each path, and follows the same semantics as `Soil.InMemoryStorage`,
 but provides synchronous access as required by ``ModelStorage``.
 It is intended for testing and prototyping. Use a persistent storage for production.
 */
public final class InMemoryModelStorage: ModelStorage, @unchecked Sendable {

    /// The root of the data tree, protected by `lock`
    private let root = Node()

    /// The lock to synchronize access from multiple threads
    private let lock = NSLock()

    /**
     Create an empty in-memory storage.
     */
    public init() { }

    // MARK: Provider

    public func tree(for path: Path, from start: Timestamp?, to end: Timestamp?, depth: Int?, limitPerNode: Int?) -> any SampleTree {
        lock.withLock {
            root.existingNode(for: path)?.tree(from: start, to: end, depth: depth, limit: limitPerNode) ?? ImmutableSampleTree()
        }
    }

    // MARK: Receiver

    @discardableResult
    public func accept(_ tree: any SampleTree, for path: Path) -> any Request {
        lock.withLock {
            root.node(for: path).save(tree)
        }
        return CompletedRequest()
    }

    // MARK: Storage

    @discardableResult
    public func delete(path: Path, from start: Timestamp?, to end: Timestamp?, depth: Int?) -> any Request {
        lock.withLock {
            root.existingNode(for: path)?.delete(from: start, to: end, depth: depth)
        }
        return CompletedRequest()
    }
}

// MARK: - Tree node

private final class Node {

    /// The samples of the node, sorted by ascending timestamp
    var samples: [Sample] = []

    /// The child nodes, indexed by their path component
    var children: [PathComponent: Node] = [:]

    func existingNode(for path: Path) -> Node? {
        var current = self
        for component in path {
            guard let child = current.children[component] else {
                return nil
            }
            current = child
        }
        return current
    }

    func node(for path: Path) -> Node {
        var current = self
        for component in path {
            if let child = current.children[component] {
                current = child
            } else {
                let child = Node()
                current.children[component] = child
                current = child
            }
        }
        return current
    }

    func save(_ tree: any SampleTree) {
        for sample in tree.samples {
            insert(sample.withTimeSet())
        }
        for (name, child) in tree.children {
            node(for: [name]).save(child)
        }
    }

    private func insert(_ sample: Sample) {
        // Most new samples are recent, so check the end first
        if let last = samples.last, last.time > sample.time {
            samples.insert(sample, at: firstIndex { $0.time > sample.time })
        } else {
            samples.append(sample)
        }
    }

    func tree(from start: Timestamp?, to end: Timestamp?, depth: Int?, limit: Int?) -> any SampleTree {
        let selected = self.samples(from: start, to: end, limit: limit)
        if let depth, depth <= 0 {
            return ImmutableSampleTree(samples: selected)
        }
        let childDepth = depth.map { $0 - 1 }
        let children = children.mapValues { $0.tree(from: start, to: end, depth: childDepth, limit: limit) }
        return ImmutableSampleTree(samples: selected, children: children)
    }

    /**
     Select samples according to the `Provider` sort and limit rules.
     */
    private func samples(from start: Timestamp?, to end: Timestamp?, limit: Int?) -> [Sample] {
        guard let start else {
            guard let end else {
                // Full history, ascending
                return limit.map { Array(samples.prefix($0)) } ?? samples
            }
            // Up to `end` (inclusive), descending
            return descending(0..<firstIndex { $0.time > end }, limit: limit)
        }
        guard let end else {
            // After `start` (exclusive), ascending
            return ascending(firstIndex { $0.time > start }..<samples.endIndex, limit: limit)
        }
        guard start < end else {
            // Reversed interval: `end` (inclusive) to `start` (exclusive), descending
            let lower = firstIndex { $0.time >= end }
            let upper = firstIndex { $0.time >= start }
            return descending(lower..<max(lower, upper), limit: limit)
        }
        let lower = firstIndex { $0.time > start }
        let upper = firstIndex { $0.time > end }
        return ascending(lower..<max(lower, upper), limit: limit)
    }

    private func ascending(_ range: Range<Int>, limit: Int?) -> [Sample] {
        let upper = limit.map { min(range.upperBound, range.lowerBound + $0) } ?? range.upperBound
        return Array(samples[range.lowerBound..<upper])
    }

    private func descending(_ range: Range<Int>, limit: Int?) -> [Sample] {
        let lower = limit.map { max(range.lowerBound, range.upperBound - $0) } ?? range.lowerBound
        return samples[lower..<range.upperBound].reversed()
    }

    func delete(from start: Timestamp?, to end: Timestamp?, depth: Int?) {
        deleteSamples(from: start, to: end)
        if let depth, depth <= 0 {
            return
        }
        let childDepth = depth.map { $0 - 1 }
        for child in children.values {
            child.delete(from: start, to: end, depth: childDepth)
        }
        // Remove empty sub-trees, so that deleted instances disappear from the tree
        children = children.filter { !$0.value.isEmpty }
    }

    private func deleteSamples(from start: Timestamp?, to end: Timestamp?) {
        samples.removeAll { sample in
            let time = sample.time
            if let start, let end, start > end {
                // Reversed interval, handled like `Soil.InMemoryStorage`
                return time >= end && time < start
            }
            // `start` is exclusive and `end` inclusive
            return (start.map { time > $0 } ?? true) && (end.map { time <= $0 } ?? true)
        }
    }

    private var isEmpty: Bool {
        samples.isEmpty && children.isEmpty
    }

    /// Binary search for the first index where the predicate is true (the predicate must be monotonic)
    private func firstIndex(where predicate: (Sample) -> Bool) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(samples[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}
