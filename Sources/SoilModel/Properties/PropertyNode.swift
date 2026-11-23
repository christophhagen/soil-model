import Foundation
import Soil

/**
 The SOIL node of a model property.

 Access the node through the projected value of a property:

 ```swift
 let node = person.$name
 print(node.path)                  // ["app", "Person", "alice", "name"]
 let yesterday = node.value(at: .now.addingTimeInterval(-86400))
 let changes = node.history()      // All values with their timestamps
 ```
 */
@MainActor
public struct PropertyNode<Value: ValueConvertible> {

    /// The model instance which contains the property
    public let model: Model

    /// The key of the property
    public let key: PathComponent

    /// The value used if no value is stored
    let defaultValue: Value

    /// The full path of the property in the storage
    public var path: Path {
        model.path + [key]
    }

    /// The most recent sample of the property, if one exists
    public var currentSample: Sample? {
        model.context.storage.sample(for: path, beforeOrAt: model.context.time)
    }

    /**
     Get the value of the property at a specific time.
     - Parameter time: The point in time (inclusive)
     - Returns: The value at the given time, or the default value
     */
    public func value(at time: Timestamp) -> Value {
        model.context.storage.value(for: path, beforeOrAt: time)
            .flatMap { Value(soilValue: $0) } ?? defaultValue
    }

    /**
     Get the history of the property.

     Samples which can't be converted to the property type are skipped.
     - Parameter start: The start of the interval (exclusive, `nil` meaning from beginning of time)
     - Parameter end: The end of the interval (inclusive, `nil` meaning up to the time of the context)
     - Returns: The values of the property in the interval, oldest first
     */
    public func history(after start: Timestamp? = nil, upTo end: Timestamp? = nil) -> [Timestamped<Value>] {
        model.context.storage.samples(for: path, after: start, upTo: end ?? model.context.time)
            .compactMap { sample in
                Value(soilValue: sample.value).map { Timestamped(value: $0, timestamp: sample.time) }
            }
    }
}

/**
 A value with the time at which it was set.
 */
public struct Timestamped<Value> {

    /// The value
    public let value: Value

    /// The time when the value was set
    public let timestamp: Timestamp

    public init(value: Value, timestamp: Timestamp) {
        self.value = value
        self.timestamp = timestamp
    }
}

extension Timestamped: Equatable where Value: Equatable { }

extension Timestamped: Sendable where Value: Sendable { }
