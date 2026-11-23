import Foundation
import Observation
import Soil

/**
 A property of a model that is persisted in the SOIL storage.

 Each property is identified by a key, which is used as the last component of the SOIL path.
 By default, the name of the property is used as the key:

 ```swift
 final class Person: Model {

     @Property
     var name: String // Stored at `root + ["Person", id, "name"]`

     @Property
     var age: Int = 18 // Uses `18` if no value is stored

     @Property("nick")
     var nickname: String? // Stored at `root + ["Person", id, "nick"]`
 }
 ```

 The key must be unique within the model, and should not be changed once data is stored.
 - Warning: Renaming a property without an explicit key changes the path, so previously stored values are no longer found.
   Specify the previous name as an explicit key when renaming properties.

 A default value is required, which is used when the storage contains no (valid) value.
 It can be omitted for optionals (defaulting to `nil`) and types conforming to ``Defaultable``.

 `@Property` can be used with all types conforming to ``ValueConvertible``.
 To link to other models, use ``Reference`` and ``ReferenceList``.

 The projected value (e.g. `person.$name`) provides access to the SOIL node of the property, including its history.
 */
@propertyWrapper
public struct Property<Value: ValueConvertible> {

    /// The key of the property, or `nil` to use the property name
    let explicitKey: PathComponent?

    /// The value to use if the storage contains no value for the property
    let defaultValue: Value

    /**
     The wrapped value is accessed through the enclosing model.
     - Warning: Direct access is not possible, since the wrapper requires the context of the enclosing model.
     */
    @available(*, unavailable, message: "@Property can only be used within subclasses of `Model`")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    /**
     The projected value is accessed through the enclosing model.
     - Warning: Direct access is not possible, since the wrapper requires the context of the enclosing model.
     */
    @available(*, unavailable, message: "@Property can only be used within subclasses of `Model`")
    public var projectedValue: PropertyNode<Value> {
        fatalError()
    }

    /**
     Create a property with a default value.
     - Parameter wrappedValue: The value to use if the storage contains no value for the property
     - Parameter key: The unique key of the property within the model. Uses the property name, if `nil`.
     */
    public init(wrappedValue: Value, _ key: PathComponent? = nil) {
        self.explicitKey = key
        self.defaultValue = wrappedValue
    }

    /**
     Create a property which uses the default value of the type.
     - Parameter key: The unique key of the property within the model. Uses the property name, if `nil`.
     */
    public init(_ key: PathComponent? = nil) where Value: Defaultable {
        self.explicitKey = key
        self.defaultValue = .default
    }

    /**
     Create an optional property, which defaults to `nil`.
     - Parameter key: The unique key of the property within the model. Uses the property name, if `nil`.
     */
    public init(_ key: PathComponent? = nil) where Value: ExpressibleByNilLiteral {
        self.explicitKey = key
        self.defaultValue = nil
    }

    /**
     Read and write the property value through the context of the enclosing model.
     */
    @MainActor
    public static subscript<M: Model>(
        _enclosingInstance instance: M,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<M, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<M, Self>
    ) -> Value {
        get {
            let wrapper = instance[keyPath: storageKeyPath]
            let key = wrapper.key(for: storageKeyPath)
            instance.access(key, keyPath: wrappedKeyPath)
            return instance.context.value(at: instance.instancePath + [key])
                .flatMap { Value(soilValue: $0) } ?? wrapper.defaultValue
        }
        set {
            let key = instance[keyPath: storageKeyPath].key(for: storageKeyPath)
            let value: Soil.Value
            do {
                value = try newValue.soilValue
            } catch {
                // Only possible for values that SOIL can't represent, e.g. `UInt64` values larger than `Int.max`
                assertionFailure("Failed to convert value for property '\(key)' of \(instance.instancePath): \(error)")
                return
            }
            instance.mutate(key, keyPath: wrappedKeyPath) {
                instance.context.set(value, at: instance.instancePath + [key])
            }
        }
    }

    /**
     Provide the SOIL node of the property, bound to the enclosing model.
     */
    @MainActor
    public static subscript<M: Model>(
        _enclosingInstance instance: M,
        projected projectedKeyPath: KeyPath<M, PropertyNode<Value>>,
        storage storageKeyPath: ReferenceWritableKeyPath<M, Self>
    ) -> PropertyNode<Value> {
        let wrapper = instance[keyPath: storageKeyPath]
        return PropertyNode(model: instance, key: wrapper.key(for: storageKeyPath), defaultValue: wrapper.defaultValue)
    }
}

extension Property: PropertyKeyed { }

extension Model {

    /// Track access to a property for observation
    func access<M: Model, T>(_ key: PathComponent, keyPath: KeyPath<M, T>) {
        let model = self as! M
        registerObservation(of: key, keyPath: keyPath)
        observationRegistrar.access(model, keyPath: keyPath)
    }

    /// Perform a mutation of a property, and notify observers
    func mutate<M: Model, T>(_ key: PathComponent, keyPath: KeyPath<M, T>, _ mutation: () -> Void) {
        let model = self as! M
        registerObservation(of: key, keyPath: keyPath)
        observationRegistrar.withMutation(of: model, keyPath: keyPath, mutation)
    }
}
