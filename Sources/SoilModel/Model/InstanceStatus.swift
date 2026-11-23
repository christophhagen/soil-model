import Soil

/**
 The status of a model instance.

 The status is stored as the value of the instance node (`root + [modelId, instanceId]`).
 */
public enum InstanceStatus: Sendable {

    /// The instance exists and is not deleted (stored as `.integer(1)`)
    case active

    /// The instance was deleted, but its data is still present (stored as `.null`)
    case deleted

    /// No status is stored for the instance
    case missing

    /// Read the status from the value of the instance node
    init(_ value: Value?) {
        switch value {
        case nil: self = .missing
        case .null: self = .deleted
        default: self = .active
        }
    }

    /// The value to store for the status
    var value: Value {
        switch self {
        case .active: .integer(1)
        case .deleted, .missing: .null
        }
    }
}

extension InstanceStatus: CustomStringConvertible {

    public var description: String {
        switch self {
        case .active: "active"
        case .deleted: "deleted"
        case .missing: "missing"
        }
    }
}
