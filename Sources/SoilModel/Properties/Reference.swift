import Soil

/**
 A reference to another model instance.

 ```swift
 final class Person: Model {

     @Reference
     var partner: Person?
 }
 ```

 The reference is stored as a SOIL `.path` value with the path of the referenced instance (relative to the context root),
 e.g. `.path(["Person", "bob"])`. References are always optional, since the referenced instance may not exist.

 References can point to subclasses of the declared type, if the subclass is registered with the context:

 ```swift
 class Animal: Model { }
 final class Dog: Animal { }

 final class Person: Model {
     @Reference
     var pet: Animal? // Can hold a `Dog`
 }
 ```

 - Note: Referenced instances are returned even if they are deleted. Check the ``Model/status`` if needed.
 */
@propertyWrapper
public struct Reference<Target: Model> {

    /// The key of the property, or `nil` to use the property name
    let explicitKey: PathComponent?

    /**
     The wrapped value is accessed through the enclosing model.
     - Warning: Direct access is not possible, since the wrapper requires the context of the enclosing model.
     */
    @available(*, unavailable, message: "@Reference can only be used within subclasses of `Model`")
    public var wrappedValue: Target? {
        get { fatalError() }
        set { fatalError() }
    }

    /**
     Create a reference.
     - Parameter key: The unique key of the property within the model. Uses the property name, if `nil`.
     */
    public init(_ key: PathComponent? = nil) {
        self.explicitKey = key
    }

    /**
     Read and write the reference through the context of the enclosing model.
     */
    @MainActor
    public static subscript<M: Model>(
        _enclosingInstance instance: M,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<M, Target?>,
        storage storageKeyPath: ReferenceWritableKeyPath<M, Self>
    ) -> Target? {
        get {
            let key = instance[keyPath: storageKeyPath].key(for: storageKeyPath)
            instance.access(key, keyPath: wrappedKeyPath)
            guard let value = instance.context.value(at: instance.instancePath + [key]) else {
                return nil
            }
            return instance.context.instance(referencedBy: value, as: Target.self)
        }
        set {
            let key = instance[keyPath: storageKeyPath].key(for: storageKeyPath)
            let value: Value = newValue?.referenceValue ?? .null
            instance.mutate(key, keyPath: wrappedKeyPath) {
                instance.context.set(value, at: instance.instancePath + [key])
            }
        }
    }
}

extension Reference: PropertyKeyed { }

extension Model {

    /// The value stored to reference the instance: The instance path as a `.path` value
    nonisolated var referenceValue: Value {
        .path(instancePath)
    }
}

extension ModelContext {

    /// Get the instance for a value stored by a reference (see ``Model/referenceValue``)
    func instance<M: Model>(referencedBy value: Value, as type: M.Type) -> M? {
        guard let path = Path(soilValue: value) else {
            return nil
        }
        return instance(at: path, as: type)
    }
}
