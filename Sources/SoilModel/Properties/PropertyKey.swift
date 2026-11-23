import Soil

/// Wrappers that store data under a key, used to collect the keys of a model
protocol PropertyKeyed {

    /// The key provided in the declaration, or `nil` if the key is derived from the property name
    var explicitKey: PathComponent? { get }
}

extension PropertyKeyed {

    /**
     Determine the key of the wrapper, using the property name if no explicit key is set.
     - Parameter storageKeyPath: The key path to the wrapper storage (e.g. `\Person._name`)
     */
    @MainActor
    func key(for storageKeyPath: AnyKeyPath) -> PathComponent {
        explicitKey ?? PropertyKey.inferred(from: storageKeyPath)
    }

    /**
     Determine the key of the wrapper, using the label from a `Mirror` if no explicit key is set.
     - Parameter label: The label of the wrapper storage (e.g. `_name`)
     */
    func key(forLabel label: String?) -> PathComponent? {
        if let explicitKey {
            return explicitKey
        }
        guard let label, label.hasPrefix("_") else {
            return nil
        }
        return String(label.dropFirst())
    }
}

/**
 Derives property keys from the names of the properties.
 */
@MainActor
enum PropertyKey {

    /// The keys determined for each wrapper storage key path
    private static var cache: [AnyKeyPath: PathComponent] = [:]

    /**
     Get the property name for the key path of a wrapper storage.

     The name is extracted from the description of the key path (e.g. `\Person._name` results in `name`).
     The description relies on the reflection metadata of the binary, which is present by default.
     - Note: If the name can't be determined, the program is stopped, to prevent storing data under a wrong path.
     */
    static func inferred(from storageKeyPath: AnyKeyPath) -> PathComponent {
        if let key = cache[storageKeyPath] {
            return key
        }
        let key = name(fromDescription: String(describing: storageKeyPath))
        cache[storageKeyPath] = key
        return key
    }

    /// Extract the property name from a key path description like `\Person._name`
    nonisolated static func name(fromDescription description: String) -> PathComponent {
        guard let separator = description.lastIndex(of: ".") else {
            failure(description)
        }
        let component = description[description.index(after: separator)...]
        guard component.hasPrefix("_"),
              component.count > 1,
              component.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            failure(description)
        }
        return String(component.dropFirst())
    }

    private nonisolated static func failure(_ description: String) -> Never {
        preconditionFailure("Unable to determine the property name from the key path '\(description)'. Provide an explicit key, e.g. `@Property(\"name\")`.")
    }
}
