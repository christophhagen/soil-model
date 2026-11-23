import Foundation
import Soil

/**
 A SOIL storage that provides synchronous access to its data.

 Models read and write their properties synchronously, so they need a storage which can answer requests immediately.
 `ModelStorage` refines the SOIL `Storage` protocol with a synchronous version of `tree(for:from:to:depth:limitPerNode:)`.
 A single synchronous implementation of that function also satisfies the asynchronous requirement of `Provider`,
 so a conforming type can be used everywhere a SOIL `Storage` is expected (e.g. with `HostedObservableStorage`).

 Conforming types must also ensure that `accept(_:for:)` and `delete(path:from:to:depth:)` are applied
 **before** the functions return, so that subsequent reads observe the changes.
 The returned request can then simply be a `CompletedRequest`.

 ```swift
 final class MyStorage: ModelStorage {

     func tree(for path: Path, from start: Timestamp?, to end: Timestamp?, depth: Int?, limitPerNode: Int?) -> any SampleTree { ... }

     func accept(_ tree: any SampleTree, for path: Path) -> any Request { ...; return CompletedRequest() }

     func delete(path: Path, from start: Timestamp?, to end: Timestamp?, depth: Int?) -> any Request { ...; return CompletedRequest() }
 }
 ```

 - Note: In asynchronous contexts the compiler prefers the `async` overload of `tree(for:...)`,
   so calls there need to be marked with `await`. Both overloads are served by the same implementation.
 */
public protocol ModelStorage: AnyObject, Storage {

    /**
     Read a data tree for a given path within a given interval.

     This is the synchronous variant of `Provider.tree(for:from:to:depth:limitPerNode:)`,
     and must follow the same rules regarding sort order and limits:
     - ascending, if `end = nil`
     - descending, if `end != nil` and `start = nil`
     - ascending, if `start < end`
     - descending, if `start > end`

     - Parameter path: The requested path.
     - Parameter start: The start of the requested interval (exclusive, `nil` meaning from beginning of time)
     - Parameter end: The end of the requested interval (inclusive, `nil` meaning to end of time)
     - Parameter depth: The number of levels below the path to include in the result (`nil` for the full sub-tree)
     - Parameter limitPerNode: The maximum number of values to return for each node of the tree (`nil` for no limit)
     - Returns: The tree with the given depth, limited to the maximum count per node, for the requested interval.
     */
    func tree(for path: Path, from start: Timestamp?, to end: Timestamp?, depth: Int?, limitPerNode: Int?) -> any SampleTree
}

extension ModelStorage {

    /**
     Get the most recent sample of a path before or at a point in time.
     - Parameter path: The requested path
     - Parameter time: The point in time (inclusive). `nil` selects the current time.
     - Returns: The most recent sample, if one exists
     */
    public func sample(for path: Path, beforeOrAt time: Timestamp? = nil) -> Sample? {
        tree(for: path, from: nil, to: time ?? .current(), depth: 0, limitPerNode: 1).samples.first
    }

    /**
     Get the value of a path at a point in time.
     - Parameter path: The requested path
     - Parameter time: The point in time (inclusive). `nil` selects the current time.
     - Returns: The most recent value, if one exists
     */
    public func value(for path: Path, beforeOrAt time: Timestamp? = nil) -> Value? {
        sample(for: path, beforeOrAt: time)?.value
    }

    /**
     Get all samples of a path in an interval, in ascending order.
     - Parameter path: The requested path
     - Parameter start: The start of the interval (exclusive, `nil` meaning from beginning of time)
     - Parameter end: The end of the interval (inclusive, `nil` meaning to end of time)
     - Returns: The samples in the interval, oldest first
     */
    public func samples(for path: Path, after start: Timestamp? = nil, upTo end: Timestamp? = nil) -> [Sample] {
        // Use a start before all samples to force ascending order
        tree(for: path, from: start ?? .distantPast, to: end ?? .distantFuture, depth: 0, limitPerNode: nil).samples
    }

    /**
     Get the current values of all direct children of a path.
     - Parameter path: The path of the parent node
     - Parameter time: The point in time (inclusive). `nil` selects the current time.
     - Returns: The most recent value of each child node, indexed by the child name. Children without values are omitted.
     */
    public func childValues(of path: Path, beforeOrAt time: Timestamp? = nil) -> [PathComponent: Value] {
        let tree = tree(for: path, from: nil, to: time ?? .current(), depth: 1, limitPerNode: 1)
        return tree.children.compactMapValues { $0.samples.first?.value }
    }
}
