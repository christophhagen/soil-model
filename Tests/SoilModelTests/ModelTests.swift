import Foundation
import Soil
import Testing
@testable import SoilModel

@MainActor
@Suite("Models")
struct ModelTests {

    let storage = InMemorySynchronousStorage()

    let context: ModelContext

    init() {
        context = ModelContext(storage: storage, root: ["app"], models: [Person.self, Animal.self, Dog.self])
    }

    @Test("Default values")
    func defaults() {
        let person = context.create(Person.self, id: "alice")
        #expect(person.name == "")
        #expect(person.age == 18)
        #expect(person.nickname == nil)
        #expect(person.priority == .low)
        #expect(person.address == nil)
        #expect(person.partner == nil)
        #expect(person.friends.isEmpty)
    }

    @Test("Values are stored at SOIL paths")
    func storagePaths() {
        let person = context.create(Person.self, id: "alice") {
            $0.name = "Alice"
            $0.priority = .high
        }
        #expect(person.path == ["app", "Person", "alice"])
        #expect(storage.value(for: ["app", "Person", "alice"]) == .integer(1))
        #expect(storage.value(for: ["app", "Person", "alice", "name"]) == .string("Alice"))
        #expect(storage.value(for: ["app", "Person", "alice", "priority"]) == .integer(1))
        #expect(person.$name.path == ["app", "Person", "alice", "name"])

        person.nickname = "Al"
        person.nickname = nil
        #expect(storage.value(for: ["app", "Person", "alice", "nick"]) == .null)
        #expect(person.nickname == nil)

        // Values written by other SOIL components are visible
        storage.accept(.integer(33), for: ["app", "Person", "alice", "age"])
        #expect(person.age == 33)

        // Invalid values fall back to the default
        storage.accept(.string("x"), for: ["app", "Person", "alice", "age"])
        #expect(person.age == 18)
    }

    @Test("Codable property")
    func codableProperty() {
        let person = context.create(Person.self)
        person.address = Address(street: "Main", city: "Bonn")
        #expect(person.address == Address(street: "Main", city: "Bonn"))
        #expect(storage.value(for: person.path + ["address"])?.mapValue?["city"] == .string("Bonn"))
    }

    @Test("Single object per instance")
    func identity() {
        let person = context.create(Person.self, id: "alice")
        #expect(context.get(Person.self, id: "alice") === person)
        #expect(context.all(Person.self).first === person)
        #expect(context.get(Person.self, id: "bob") == nil)
    }

    @Test("References")
    func references() {
        let alice = context.create(Person.self, id: "alice")
        let bob = context.create(Person.self, id: "bob")
        alice.partner = bob
        #expect(alice.partner === bob)
        #expect(storage.value(for: alice.path + ["partner"]) == .path(["Person", "bob"]))
        alice.partner = nil
        #expect(alice.partner == nil)

        alice.friends = [bob, alice]
        #expect(alice.friends == [bob, alice])
        #expect(storage.value(for: alice.path + ["friends"]) == .list([.path(["Person", "bob"]), .path(["Person", "alice"])]))
    }

    @Test("Polymorphic references")
    func polymorphicReferences() {
        let alice = context.create(Person.self, id: "alice")
        let dog = context.create(Dog.self, id: "rex") {
            $0.name = "Rex"
            $0.breed = "Beagle"
        }
        let cat = context.create(Animal.self, id: "tom")
        alice.pet = dog
        #expect(storage.value(for: alice.path + ["pet"]) == .path(["dog", "rex"]))
        #expect(alice.pet === dog)
        #expect((alice.pet as? Dog)?.breed == "Beagle")
        #expect(alice.pet?.name == "Rex")

        alice.pets = [cat, dog]
        #expect(alice.pets.map(\.id) == ["tom", "rex"])
        #expect(alice.pets.last is Dog)

        // References to unrelated types are not resolved
        storage.accept(.path(["Person", "alice"]), for: alice.path + ["pet"])
        #expect(alice.pet == nil)
    }

    @Test("Delete, restore and purge")
    func deletion() {
        let alice = context.create(Person.self, id: "alice") { $0.name = "Alice" }
        let bob = context.create(Person.self, id: "bob")
        bob.partner = alice

        alice.delete()
        #expect(alice.status == .deleted)
        #expect(context.all(Person.self) == [bob])
        #expect(context.active(Person.self, id: "alice") == nil)
        #expect(context.get(Person.self, id: "alice") === alice)
        // References still resolve, and data is kept
        #expect(bob.partner?.status == .deleted)
        #expect(alice.name == "Alice")

        alice.restore()
        #expect(alice.status == .active)
        #expect(Set(context.all(Person.self)) == [alice, bob])

        alice.purge()
        #expect(alice.status == .missing)
        #expect(alice.name == "")
        #expect(context.get(Person.self, id: "alice") == nil)
        #expect(storage.tree(for: alice.path, from: nil, to: nil, depth: nil, limitPerNode: nil).isEmpty)
    }

    @Test("Filtering instances")
    func filtering() {
        context.create(Person.self, id: "a") { $0.age = 10 }
        context.create(Person.self, id: "b") { $0.age = 20 }
        context.create(Dog.self, id: "c")
        #expect(context.all(Person.self, where: { $0.age > 15 }).map(\.id) == ["b"])
        #expect(context.all(Person.self).count == 2)
        #expect(context.all(Dog.self).count == 1)
    }

    @Test("History and snapshots")
    func history() throws {
        let alice = context.create(Person.self, id: "alice") { $0.name = "A" }
        let first = Timestamp.current()
        alice.name = "B"
        alice.name = "C"

        #expect(alice.$name.history().map(\.value) == ["A", "B", "C"])
        #expect(alice.$name.value(at: first) == "A")
        #expect(alice.$name.history(after: first).map(\.value) == ["B", "C"])

        let snapshot = context.snapshot(at: first)
        #expect(snapshot.isReadOnly)
        let old = try #require(snapshot.get(Person.self, id: "alice"))
        #expect(old !== alice)
        #expect(old.name == "A")
        #expect(old.$name.history().map(\.value) == ["A"])

        // Instances created after the snapshot are not visible
        context.create(Person.self, id: "bob")
        #expect(snapshot.all(Person.self).map(\.id) == ["alice"])
    }

    @Test("Custom model id")
    func customModelId() {
        #expect(Dog.modelId == "dog")
        #expect(Animal.modelId == "Animal")
        let dog = context.create(Dog.self, id: "rex")
        #expect(dog.path == ["app", "dog", "rex"])
    }

    @Test("Property keys")
    func propertyKeys() {
        #expect(Set(context.propertyKeys(of: Dog.self)) == ["name", "breed"])
        #expect(Set(context.propertyKeys(of: Person.self)) == ["name", "age", "nick", "priority", "address", "partner", "friends", "pet", "pets"])
        let keys = context.propertyKeys(of: DuplicateKeys.self)
        #expect(keys == ["value", "value"])
    }

    @Test("Keys inferred from property names")
    func inferredKeys() {
        let alice = context.create(Person.self, id: "alice") {
            $0.name = "Alice"
            $0.nickname = "Al"
            $0.friends = [$0]
        }
        let rex = context.create(Dog.self, id: "rex") { $0.breed = "Beagle" }
        alice.pet = rex
        #expect(storage.value(for: alice.path + ["name"]) == .string("Alice"))
        #expect(storage.value(for: alice.path + ["nick"]) == .string("Al"))
        #expect(storage.value(for: alice.path + ["friends"]) == .list([.path(["Person", "alice"])]))
        #expect(storage.value(for: alice.path + ["pet"]) == .path(["dog", "rex"]))
        #expect(storage.value(for: rex.path + ["breed"]) == .string("Beagle"))
        #expect(alice.$name.key == "name")
        #expect(alice.$nickname.key == "nick")
    }

    @Test("Parsing key path descriptions", arguments: [
        ("\\Person._name", "name"),
        ("\\Outer.Inner._value2", "value2"),
        ("\\Person.__private", "_private"),
    ])
    func keyPathDescriptions(description: String, expected: String) {
        #expect(PropertyKey.name(fromDescription: description) == expected)
    }
}
