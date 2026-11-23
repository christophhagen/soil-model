import Foundation
import Observation
import Soil
import Testing
@testable import SoilModel

/// A thread-safe flag to record observation callbacks
private final class Flag: @unchecked Sendable {

    private let lock = NSLock()

    private var value = false

    func set() { lock.withLock { value = true } }

    var isSet: Bool { lock.withLock { value } }
}

@MainActor
@Suite("Observation")
struct ObservationTests {

    let storage = InMemoryModelStorage()

    let context: ModelContext

    init() {
        context = ModelContext(storage: storage, root: ["app"], models: [Person.self])
    }

    private func observe(_ access: @escaping () -> Void) -> Flag {
        let flag = Flag()
        withObservationTracking(access) { flag.set() }
        return flag
    }

    @Test("Local changes")
    func localChanges() {
        let alice = context.create(Person.self, id: "alice")
        let nameChanged = observe { _ = alice.name }
        let ageChanged = observe { _ = alice.age }
        alice.name = "Alice"
        #expect(nameChanged.isSet)
        #expect(!ageChanged.isSet)
    }

    @Test("Instance list changes")
    func instanceChanges() {
        let alice = context.create(Person.self, id: "alice")
        var changed = observe { _ = context.all(Person.self) }
        context.create(Person.self, id: "bob")
        #expect(changed.isSet)

        changed = observe { _ = context.all(Person.self) }
        alice.delete()
        #expect(changed.isSet)
    }

    @Test("External changes through the receiver")
    func externalChanges() async {
        let alice = context.create(Person.self, id: "alice")
        let nameChanged = observe { _ = alice.name }
        let ageChanged = observe { _ = alice.age }
        let statusChanged = observe { _ = alice.status }
        let listChanged = observe { _ = context.all(Person.self) }

        let tree = ImmutableSampleTree(children: [
            "alice": ImmutableSampleTree(children: ["name": ImmutableSampleTree(value: .string("Alice"))]),
            "bob": ImmutableSampleTree(value: .integer(1)),
        ])
        await context.receiver.accept(tree, for: ["app", "Person"]).wait()

        #expect(nameChanged.isSet)
        #expect(!ageChanged.isSet)
        #expect(!statusChanged.isSet)
        #expect(listChanged.isSet)
        #expect(alice.name == "Alice")
        #expect(context.all(Person.self).count == 2)
    }

    @Test("External changes above the root")
    func changesAboveRoot() async {
        let alice = context.create(Person.self, id: "alice")
        let statusChanged = observe { _ = alice.status }
        let tree = ImmutableSampleTree(children: [
            "app": ImmutableSampleTree(children: [
                "Person": ImmutableSampleTree(children: ["alice": ImmutableSampleTree(value: .null)])
            ]),
            "other": ImmutableSampleTree(value: .integer(3)),
        ])
        await context.receiver.accept(tree, for: []).wait()
        #expect(statusChanged.isSet)
        #expect(alice.status == .deleted)
    }

    @Test("Subscription from an observable SOIL storage")
    func subscription() async {
        // A storage of another component, which provides updates to subscribers
        let remote = ObservingStorage(wrapping: InMemoryStorage())
        await remote.setReceiver(context.receiver).wait()
        await remote.include(context.root, depth: nil).wait()

        let alice = context.create(Person.self, id: "alice")
        let nameChanged = observe { _ = alice.name }

        await remote.accept(.string("Remote Alice"), for: ["app", "Person", "alice", "name"]).wait()
        // Ignored, since it's not part of the subscription
        await remote.accept(.integer(1), for: ["other"]).wait()

        #expect(nameChanged.isSet)
        #expect(alice.name == "Remote Alice")
        #expect(storage.value(for: ["other"]) == nil)
    }
}
