import Soil

/**
 A list of references to other model instances.

 ```swift
 final class Person: Model {

     @ReferenceList
     var friends: [Person]
 }
 ```

 The list is stored as a SOIL `.list` of reference values (see ``Reference``), each with the path of a referenced instance (relative to the context root).
 It can be used with all collections conforming to ``SequenceInitializable``, like `Array`, `ContiguousArray` and `Set`.
 Like ``Reference``, the list can contain instances of registered subclasses.

 - Note: Paths that can't be resolved to an instance of the element type are skipped.
 */
@propertyWrapper
public struct ReferenceList<S: SequenceInitializable> where S.Element: Model {

    /// The key of the property, or `nil` to use the property name
    let explicitKey: PathComponent?

    /**
     The wrapped value is accessed through the enclosing model.
     - Warning: Direct access is not possible, since the wrapper requires the context of the enclosing model.
     */
    @available(*, unavailable, message: "@ReferenceList can only be used within subclasses of `Model`")
    public var wrappedValue: S {
        get { fatalError() }
        set { fatalError() }
    }

    /**
     Create a reference list.
     - Parameter key: The unique key of the property within the model. Uses the property name, if `nil`.
     */
    public init(_ key: PathComponent? = nil) {
        self.explicitKey = key
    }

    /**
     Read and write the list through the context of the enclosing model.
     */
    @MainActor
    public static subscript<M: Model>(
        _enclosingInstance instance: M,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<M, S>,
        storage storageKeyPath: ReferenceWritableKeyPath<M, Self>
    ) -> S {
        get {
            let key = instance[keyPath: storageKeyPath].key(for: storageKeyPath)
            instance.access(key, keyPath: wrappedKeyPath)
            guard case .list(let values) = instance.context.value(at: instance.instancePath + [key]) else {
                return S([])
            }
            return S(values.compactMap { instance.context.instance(referencedBy: $0, as: S.Element.self) })
        }
        set {
            let key = instance[keyPath: storageKeyPath].key(for: storageKeyPath)
            let value: Value = .list(newValue.map(\.referenceValue))
            instance.mutate(key, keyPath: wrappedKeyPath) {
                instance.context.set(value, at: instance.instancePath + [key])
            }
        }
    }
}

extension ReferenceList: PropertyKeyed { }
