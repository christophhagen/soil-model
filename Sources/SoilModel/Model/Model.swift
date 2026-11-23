import Foundation
import Observation
import Soil

/**
 The base class for all models stored in a SOIL storage.

 Subclass `Model` and annotate the persisted properties with ``Property``, ``Reference`` or ``ReferenceList``:

 ```swift
 final class Person: Model {

     @Property
     var name: String

     @Property
     var age: Int = 18

     @Reference
     var partner: Person?

     @ReferenceList
     var friends: [Person]
 }
 ```

 Each instance is stored in the SOIL tree of its ``ModelContext``:

 ```
 root + [modelId]                            all instances of the model
 root + [modelId, instanceId]                instance status (`.integer(1)`: active, `.null`: deleted)
 root + [modelId, instanceId, propertyKey]   property values
 ```

 Models are observable (using the `Observation` framework), and can be used directly in SwiftUI views.
 Instances should only be created through the context (e.g. ``ModelContext/create(_:id:configure:)``),
 which ensures that only a single object exists for each instance.
 */
@MainActor
open class Model: nonisolated Observation.Observable, nonisolated Identifiable, nonisolated Hashable {

    /**
     The unique id of the model type, used as the path component for all instances.

     Defaults to the name of the class. Override it to keep the stored data accessible when the class is renamed.

     ```swift
     final class Person: Model {
         override class var modelId: PathComponent { "person" }
     }
     ```
     */
    open nonisolated class var modelId: PathComponent {
        String(describing: self)
    }

    /// The unique id of the instance among all instances of the model
    public nonisolated let id: PathComponent

    /// The context that manages the instance
    public unowned let context: ModelContext

    /// The registrar to track access and changes to the properties
    let observationRegistrar = ObservationRegistrar()

    /// Functions to notify observers about external changes, indexed by property key.
    /// Filled when properties are accessed, since the key paths are only known at that point.
    private var propertyNotifications: [PathComponent: (Model) -> Void] = [:]

    /**
     Create a model instance.
     - Warning: Don't call this initializer directly. Use the functions of ``ModelContext`` to create or get instances.
     - Parameter context: The context which manages the instance
     - Parameter id: The unique id of the instance
     */
    public required init(context: ModelContext, id: PathComponent) {
        self.context = context
        self.id = id
    }

    // MARK: Paths

    /// The path of the instance, relative to the root of the context
    public nonisolated var instancePath: Path {
        [Self.modelId, id]
    }

    /// The full path of the instance in the storage
    public var path: Path {
        context.root + instancePath
    }

    // MARK: Status

    /// The current status of the instance
    public var status: InstanceStatus {
        observationRegistrar.access(self, keyPath: \.status)
        return InstanceStatus(context.value(at: instancePath))
    }

    /**
     Mark the instance as deleted.

     The data of the instance is kept, so that the instance can be restored using ``restore()``.
     Deleted instances are not returned by ``ModelContext/all(_:where:)``.
     To also remove all data of the instance, use ``purge()``.
     */
    public func delete() {
        guard status == .active else { return }
        context.setStatus(.deleted, of: self)
    }

    /**
     Restore a deleted instance.
     */
    public func restore() {
        guard status == .deleted else { return }
        context.setStatus(.active, of: self)
    }

    /**
     Remove the instance and all of its data (including the history) from the storage.
     */
    public func purge() {
        context.purge(self)
    }

    // MARK: Observation

    /**
     Register a key path for a property, so that external changes can be forwarded to observers.
     */
    func registerObservation<M: Model, T>(of key: PathComponent, keyPath: KeyPath<M, T>) {
        guard propertyNotifications[key] == nil else {
            return
        }
        propertyNotifications[key] = { model in
            let model = model as! M
            model.observationRegistrar.withMutation(of: model, keyPath: keyPath) { }
        }
    }

    /**
     Notify observers that a property has changed.
     */
    func notifyChange(of key: PathComponent) {
        propertyNotifications[key]?(self)
    }

    /**
     Notify observers that the status has changed.
     */
    func notifyStatusChange() {
        observationRegistrar.withMutation(of: self, keyPath: \.status) { }
    }

    /**
     Notify observers that all properties have changed.
     */
    func notifyAllChanges() {
        notifyStatusChange()
        for notify in propertyNotifications.values {
            notify(self)
        }
    }

    // MARK: Hashable

    public nonisolated static func == (lhs: Model, rhs: Model) -> Bool {
        type(of: lhs).modelId == type(of: rhs).modelId && lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(Self.modelId)
        hasher.combine(id)
    }
}
