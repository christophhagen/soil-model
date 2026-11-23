# SoilModel

Define relational data models in Swift, and store them in a synchronous [SOIL](https://github.com/DLR-RB/soil-core-swift) storage.

```swift
import Soil
import SoilModel

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

let context = ModelContext(storage: InMemoryModelStorage(), root: ["app"], models: [Person.self])

let alice = context.create(Person.self, id: "alice") { $0.name = "Alice" }
alice.age += 1
```

The library is based on the design of [StateModel](https://github.com/christophhagen/StateModel), adapted to SOIL concepts:
models are flattened into SOIL paths, all values are timestamped samples, and synchronization is handled by SOIL components.
It requires no macros (and therefore no `swift-syntax`).

## Storage layout

All data of a context is stored below its `root` path:

| Path | Content |
| --- | --- |
| `root + [modelId]` | The node containing all instances of a model |
| `root + [modelId, instanceId]` | The instance status: `.integer(1)` (active) or `.null` (deleted) |
| `root + [modelId, instanceId, propertyKey]` | The property values |

For the example above, the name of Alice is stored at `["app", "Person", "alice", "name"]`.
The model id defaults to the class name, and can be overridden to keep data accessible when renaming the class:

```swift
final class Person: Model {
    override class var modelId: String { "person" }
}
```

## Property keys

By default, the name of the Swift property is used as the key.
Provide an explicit key to choose a different name, or to keep the stored path when renaming a property:

```swift
@Property("nick")
var nickname: String? // Stored at `root + ["Person", id, "nick"]`
```

> Renaming a property without an explicit key changes its path, so previously stored values are no longer found.

Keys are inferred from the key path of the wrapper storage (e.g. `\Person._name` becomes `name`),
which relies on the reflection metadata that Swift includes by default.
If reflection metadata is stripped (`-disable-reflection-metadata`), the name can't be determined,
and the program stops with an error asking for an explicit key.

## Model definition

Models subclass `Model`, and annotate persisted properties with property wrappers:

- `@Property` for all types conforming to `ValueConvertible`
- `@Reference` for links to other models (stored as the instance path, a `.path` value)
- `@ReferenceList` for lists of links (stored as a `.list` of instance paths)

Each wrapper accepts an optional explicit key, e.g. `@Property("name")`.

Keys must be unique within a model. In debug builds, `ModelContext.register(_:)` checks for duplicate keys.

### Values

Values are converted using the `ValueConvertible` protocol of SOIL, which maps them to native SOIL values, so other SOIL components can read them:

| Swift type | SOIL value |
| --- | --- |
| `Int` (and all fixed-width integers) | `.integer` (values larger than `Int.max` can't be stored) |
| `Bool` | `.integer` (`0` or `1`) |
| `Double`, `Float` | `.double` |
| `String` | `.string` |
| `Data` | `.data` |
| `Date` | `.double` (seconds since 1970) |
| `UUID`, `URL` | `.string` |
| `Optional` | `.null` for `nil` |
| `Array`, `Set` | `.list` |
| `[String: T]` | `.map` |

Enums with raw values and `Codable` types only need to declare conformance:

```swift
enum Priority: Int, ValueConvertible {
    case low, high
}

struct Address: Codable, ValueConvertible {
    var street: String
    var city: String
}
```

`Codable` types are stored as `.map` / `.list` values using the `ValueEncoder` and `ValueDecoder` of SOIL.

### Default values

Each property has a default value, which is used if no (valid) value is stored.
It can be omitted for optionals (`nil`) and types conforming to `Defaultable` (e.g. `0`, `""`, `[]`).

### References

References can point to subclasses of the declared type, if the subclass is registered with the context:

```swift
class Animal: Model { }
final class Dog: Animal { }

final class Person: Model {
    @Reference
    var pet: Animal? // Can hold a `Dog`
}
```

## Usage

```swift
let bob = context.create(Person.self)               // Random UUID as id
let alice = context.get(Person.self, id: "alice")   // Also returns deleted instances
let active = context.active(Person.self, id: "alice")
let adults = context.all(Person.self, where: { $0.age >= 18 })

alice.delete()   // Marks the instance as deleted, keeps all data
alice.restore()  // Undo the deletion
alice.purge()    // Removes all data, including the history
```

### History

Every write is stored as a timestamped sample, so the history of each property is available:

```swift
alice.$name.path                 // ["app", "Person", "alice", "name"]
alice.$name.history()            // All values with timestamps
alice.$name.value(at: yesterday) // The value at a point in time

let snapshot = context.snapshot(at: yesterday) // A read-only context showing past data
let oldAlice = snapshot.get(Person.self, id: "alice")
```

### SwiftUI

Models and contexts use the `Observation` framework, and can be used directly in views:

```swift
struct PeopleView: View {

    @Query(filter: { $0.age >= 18 }, sortBy: \.name)
    var adults: [Person]

    var body: some View {
        List(adults) { person in
            Text(person.name)
        }
    }
}

PeopleView().environment(context)
```

## Storage

Models require a `ModelStorage`, which is a SOIL `Storage` with synchronous reads:

```swift
public protocol ModelStorage: AnyObject, Storage {
    func tree(for path: Path, from start: Timestamp?, to end: Timestamp?, depth: Int?, limitPerNode: Int?) -> any SampleTree
}
```

The synchronous `tree` function also satisfies the asynchronous requirement of SOIL's `Provider`.
Conforming types must apply `accept(_:for:)` and `delete(path:from:to:depth:)` before returning.

`InMemoryModelStorage` is provided for testing and prototyping. Persistent storages are implemented in separate packages.

> In asynchronous contexts, the compiler prefers SOIL's `async` overloads of `tree(for:...)` and `samples(for:)`,
> so these calls need to be marked with `await`.

## Synchronization

Since a `ModelStorage` is a SOIL `Storage`, it can be shared with all SOIL components, e.g. using `HostedObservableStorage`.
To receive updates from other components, use the `receiver` of the context.
It stores incoming data and notifies the affected models:

```swift
let remote = await RemoteObservableStorage(connection: connection)
await remote.setReceiver(context.receiver).wait()
await remote.include(context.root, depth: nil).wait()
```

If data is written to the storage by other means, call `context.storageDidChange(_:at:)` to notify observers.

## Differences to StateModel

- No macros: models subclass `Model`, and property keys are derived from the property names (or set explicitly)
- String ids for models, instances and properties, forming readable SOIL paths
- No custom synchronization layer, since SOIL provides hosting, remote access and subscriptions
- Built-in history for all properties, and read-only snapshots instead of `HistoryView`
- Polymorphic references
- Native SOIL values instead of encoded data
- Fine-grained observation using `Observation` instead of `ObservableObject`
- Not (yet) supported: editing contexts, commands
