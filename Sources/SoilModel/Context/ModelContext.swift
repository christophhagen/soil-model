import Foundation
import Observation
import Soil

/**
 The context that connects models to a SOIL storage.

 A context manages the instances of models stored in a ``ModelStorage``.
 It ensures that only a single object exists for each instance, so that changes are visible to all observers.

 ```swift
 let storage = InMemoryModelStorage()
 let context = ModelContext(storage: storage, root: ["app"], models: [Person.self])

 let alice = context.create(Person.self, id: "alice") { $0.name = "Alice" }
 let people = context.all(Person.self)
 ```

 All model data is placed below the `root` path of the context, which allows integrating the models into a larger SOIL tree.
 The storage can be shared with other SOIL components (e.g. `HostedObservableStorage`) to synchronize the data.
 Use ``receiver`` to feed external updates into the storage, so that models are notified about the changes.
 */
@MainActor
public final class ModelContext: nonisolated Observation.Observable {

    /// The storage containing the model data
    public let storage: any ModelStorage

    /// The path below which all model data is stored
    public let root: Path

    /// The point in time of the data, or `nil` for the current data.
    /// Contexts with a fixed time are read-only (see ``snapshot(at:)``).
    public let time: Timestamp?

    /// The registered model types, indexed by their model id
    private var registeredTypes: [PathComponent: Model.Type] = [:]

    /// The registrar to track changes to the set of instances
    private let observationRegistrar = ObservationRegistrar()

    /// Weak references to all instance objects, to provide a single object for each instance
    private var instances: [InstanceKey: WeakModel] = [:]

    /// The number of instances created since the last removal of released objects
    private var insertionsSinceCleanup = 0

    /**
     Create a context.
     - Parameter storage: The storage containing the model data
     - Parameter root: The path below which all model data is stored
     - Parameter models: The model types to register (see ``register(_:)``)
     */
    public init(storage: any ModelStorage, root: Path = [], models: [Model.Type] = []) {
        self.storage = storage
        self.root = root
        self.time = nil
        models.forEach(register)
    }

    private init(snapshotOf context: ModelContext, at time: Timestamp) {
        self.storage = context.storage
        self.root = context.root
        self.time = time
        self.registeredTypes = context.registeredTypes
    }

    /// `true`, if the context is a read-only snapshot
    public var isReadOnly: Bool {
        time != nil
    }

    // MARK: Registration

    /**
     Register a model type.

     Registration is required to resolve references to subclasses of the declared reference type,
     and to forward external changes to observers of all instances.
     In debug builds, the model is also checked for duplicate property keys.
     - Parameter type: The model type to register
     */
    public func register(_ type: Model.Type) {
        let modelId = type.modelId
        if let existing = registeredTypes[modelId], existing != type {
            assertionFailure("Model id '\(modelId)' is used by \(existing) and \(type)")
        }
        registeredTypes[modelId] = type
#if DEBUG
        let keys = propertyKeys(of: type)
        assert(!keys.contains(""), "Empty property key in \(type)")
        assert(Set(keys).count == keys.count, "Duplicate property keys in \(type): \(keys.sorted())")
#endif
    }

    /// Collect the keys of all properties of a model (including superclasses) by reflecting a temporary instance
    func propertyKeys(of type: Model.Type) -> [PathComponent] {
        let probe = type.init(context: self, id: "")
        var keys: [PathComponent] = []
        var mirror: Mirror? = Mirror(reflecting: probe)
        while let current = mirror {
            keys += current.children.compactMap { child in
                (child.value as? PropertyKeyed)?.key(forLabel: child.label)
            }
            mirror = current.superclassMirror
        }
        return keys
    }

    // MARK: Instances

    /**
     Create a new instance.

     If an instance with the id already exists, it is marked as active and returned.
     - Parameter type: The model type of the instance
     - Parameter id: The unique id of the instance (defaults to a new UUID)
     - Parameter configure: A closure to set initial property values
     - Returns: The created instance
     */
    @discardableResult
    public func create<M: Model>(_ type: M.Type = M.self, id: PathComponent = UUID().uuidString, configure: (M) -> Void = { _ in }) -> M {
        let instance: M = object(M.self, id: id)
        setStatus(.active, of: instance)
        configure(instance)
        return instance
    }

    /**
     Get an instance by its id.
     - Note: This function also returns deleted instances. Use ``active(_:id:)`` to only get non-deleted instances.
     - Parameter type: The model type of the instance
     - Parameter id: The id of the instance
     - Returns: The instance, if it exists in the storage
     */
    public func get<M: Model>(_ type: M.Type = M.self, id: PathComponent) -> M? {
        let instance: M = object(M.self, id: id)
        return instance.status == .missing ? nil : instance
    }

    /**
     Get an instance by its id, if it is not deleted.
     - Parameter type: The model type of the instance
     - Parameter id: The id of the instance
     - Returns: The instance, if it exists in the storage and is active
     */
    public func active<M: Model>(_ type: M.Type = M.self, id: PathComponent) -> M? {
        let instance: M = object(M.self, id: id)
        return instance.status == .active ? instance : nil
    }

    /**
     Get all active instances of a model.

     When used within an observation scope (e.g. a SwiftUI view), the observer is notified when instances are created or deleted.
     - Parameter type: The model type
     - Parameter isIncluded: A filter to select instances
     - Returns: All active instances which match the filter
     */
    public func all<M: Model>(_ type: M.Type = M.self, where isIncluded: (M) -> Bool = { _ in true }) -> [M] {
        let modelId = M.modelId
        observationRegistrar.access(self, keyPath: \.[instancesOf: modelId])
        return storage.childValues(of: root + [modelId], beforeOrAt: time)
            .compactMap { id, value -> M? in
                guard InstanceStatus(value) == .active else {
                    return nil
                }
                let instance: M = object(M.self, id: id)
                return isIncluded(instance) ? instance : nil
            }
    }

    /**
     Create a read-only context which shows the data at a specific point in time.

     Models from the snapshot behave like normal models, but all modifications are ignored.
     - Parameter time: The point in time to show
     - Returns: A read-only context
     */
    public func snapshot(at time: Timestamp) -> ModelContext {
        ModelContext(snapshotOf: self, at: time)
    }

    // MARK: Internal access

    /**
     Get an instance for a path relative to the root.

     The path must consist of the model id and the instance id.
     If the model id differs from the requested type, the registered type is used, if it is a subclass.
     */
    func instance<M: Model>(at path: Path, as type: M.Type) -> M? {
        guard path.count == 2 else {
            return nil
        }
        let (modelId, id) = (path[0], path[1])
        if modelId == M.modelId {
            return object(M.self, id: id)
        }
        guard let registered = registeredTypes[modelId] else {
            return nil
        }
        return object(registered, id: id) as? M
    }

    /// Read the value at a path relative to the root
    func value(at path: Path) -> Value? {
        storage.value(for: root + path, beforeOrAt: time)
    }

    /// Write a value at a path relative to the root
    func set(_ value: Value, at path: Path) {
        guard !isReadOnly else {
            assertionFailure("Attempt to modify a read-only snapshot at \(path)")
            return
        }
        storage.accept(Sample(value: value, timestamp: .current()), for: root + path)
    }

    /// Set the status of an instance, and notify observers
    func setStatus(_ status: InstanceStatus, of instance: Model) {
        set(status.value, at: instance.instancePath)
        instance.notifyStatusChange()
        notifyInstancesChanged(of: type(of: instance).modelId)
    }

    /// Remove all data of an instance, and notify observers
    func purge(_ instance: Model) {
        guard !isReadOnly else {
            assertionFailure("Attempt to purge \(instance.instancePath) from a read-only snapshot")
            return
        }
        storage.delete(path: instance.path, from: nil, to: nil, depth: nil)
        instance.notifyAllChanges()
        notifyInstancesChanged(of: type(of: instance).modelId)
    }

    // MARK: Observation

    /// A value to observe changes to the instances of a model
    subscript(instancesOf modelId: PathComponent) -> Void {
        ()
    }

    private func notifyInstancesChanged(of modelId: PathComponent) {
        observationRegistrar.withMutation(of: self, keyPath: \.[instancesOf: modelId]) { }
    }

    /**
     Notify observers about changes to the data in the storage.

     This function is called by ``receiver`` for external updates.
     Call it manually if data is written to the storage without using the context or its receiver.
     - Parameter tree: The tree with the changed data
     - Parameter path: The full path of the tree in the storage
     */
    public func storageDidChange(_ tree: any SampleTree, at path: Path) {
        if path.hasPrefix(root) {
            notify(about: tree, at: path.removing(prefix: root))
            return
        }
        guard root.hasPrefix(path) else {
            // Unrelated data
            return
        }
        // Select the part of the tree below the root
        var current: (any SampleTree)? = tree
        for component in root.removing(prefix: path) {
            current = current?.children[component]
        }
        if let current {
            notify(about: current, at: [])
        }
    }

    /// Notify observers about changes, with the path relative to the root
    private func notify(about tree: any SampleTree, at path: Path) {
        switch path.count {
        case 0:
            for (modelId, child) in tree.children {
                notify(about: child, at: [modelId])
            }
        case 1:
            for (id, child) in tree.children {
                notify(about: child, at: path + [id])
            }
        case 2:
            let modelId = path[0]
            guard let instance = cachedObject(model: modelId, id: path[1]) else {
                // Notify queries, since a new instance may have been created
                if !tree.samples.isEmpty {
                    notifyInstancesChanged(of: modelId)
                }
                return
            }
            if !tree.samples.isEmpty {
                instance.notifyStatusChange()
                notifyInstancesChanged(of: modelId)
            }
            for key in tree.children.keys {
                instance.notifyChange(of: key)
            }
        default:
            // Changes to properties (or nested values of properties)
            cachedObject(model: path[0], id: path[1])?.notifyChange(of: path[2])
        }
    }

    // MARK: Object cache

    private struct InstanceKey: Hashable {
        let model: PathComponent
        let id: PathComponent
    }

    private struct WeakModel {
        weak var value: Model?
    }

    private func cachedObject(model: PathComponent, id: PathComponent) -> Model? {
        instances[InstanceKey(model: model, id: id)]?.value
    }

    /// Get the single object for an instance, or create it
    private func object<M: Model>(_ type: M.Type, id: PathComponent) -> M {
        let key = InstanceKey(model: type.modelId, id: id)
        if let existing = instances[key]?.value as? M {
            return existing
        }
        let object = type.init(context: self, id: id)
        instances[key] = WeakModel(value: object)
        removeReleasedObjectsIfNeeded()
        return object
    }

    private func removeReleasedObjectsIfNeeded() {
        insertionsSinceCleanup += 1
        guard insertionsSinceCleanup >= 1000 else {
            return
        }
        insertionsSinceCleanup = 0
        instances = instances.filter { $0.value.value != nil }
    }
}
