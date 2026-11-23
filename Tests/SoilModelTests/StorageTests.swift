import Foundation
import Soil
import Testing
@testable import SoilModel

@Suite("In-memory synchronous storage")
struct StorageTests {

    private let base = Date(timeIntervalSince1970: 1000)

    private func time(_ offset: Double) -> Timestamp {
        base.addingTimeInterval(offset)
    }

    /// Fill both storages with the same data
    private func makeStorages() async -> (InMemorySynchronousStorage, InMemoryStorage) {
        let model = InMemorySynchronousStorage()
        let reference = InMemoryStorage()
        let tree = ImmutableSampleTree(
            samples: (1...5).map { Sample(value: .integer($0), timestamp: time(Double($0))) },
            children: [
                "a": ImmutableSampleTree(
                    samples: [Sample(value: .string("x"), timestamp: time(2)), Sample(value: .string("y"), timestamp: time(4))],
                    children: ["b": ImmutableSampleTree(sample: Sample(value: .integer(9), timestamp: time(3)))]
                )
            ]
        )
        model.accept(tree, for: ["root"])
        await reference.accept(tree, for: ["root"]).wait()
        return (model, reference)
    }

    @Test("Same results as Soil.InMemoryStorage", arguments: [
        (nil, nil, nil, nil),
        (nil, nil, nil, 2),
        (nil, 3.0, 0, 1),
        (nil, 3.5, nil, 2),
        (1.0, nil, nil, 2),
        (1.0, 4.0, 1, nil),
        (4.0, 1.0, nil, 2),
        (2.0, 2.0, nil, nil),
    ] as [(Double?, Double?, Int?, Int?)])
    func sameResults(start: Double?, end: Double?, depth: Int?, limit: Int?) async {
        let (model, reference) = await makeStorages()
        let expected = await reference.tree(for: ["root"], from: start.map(time), to: end.map(time), depth: depth, limitPerNode: limit)
        let result = model.tree(for: ["root"], from: start.map(time), to: end.map(time), depth: depth, limitPerNode: limit)
        #expect(result.isEqual(to: expected), "\(result)\n!=\n\(expected)")
    }

    @Test("Delete intervals", arguments: [
        (nil, nil),
        (nil, 3.0),
        (2.0, nil),
        (1.0, 4.0),
        (4.0, 1.0),
    ] as [(Double?, Double?)])
    func delete(start: Double?, end: Double?) async {
        let (model, reference) = await makeStorages()
        model.delete(path: ["root"], from: start.map(time), to: end.map(time), depth: 0)
        await reference.delete(path: ["root"], from: start.map(time), to: end.map(time), depth: 0).wait()
        let expected = await reference.samples(for: ["root"])
        #expect(await model.samples(for: ["root"]) == expected)
    }

    @Test("Delete sub-tree")
    func deleteTree() async {
        let (model, _) = await makeStorages()
        model.delete(path: ["root"], from: nil, to: nil, depth: nil)
        #expect(model.tree(for: [], from: nil, to: nil, depth: nil, limitPerNode: nil).isEmpty)
    }

    @Test("Usable as SOIL storage")
    func asyncAccess() async {
        let storage: any Storage = InMemorySynchronousStorage()
        await storage.accept(.integer(1), for: ["a"]).wait()
        #expect(await storage.currentValue(for: ["a"]) == .integer(1))
    }

    @Test("Child values")
    func childValues() async {
        let (model, _) = await makeStorages()
        #expect(model.childValues(of: ["root"]) == ["a": .string("y")])
        #expect(model.childValues(of: ["root"], beforeOrAt: time(3)) == ["a": .string("x")])
        #expect(model.value(for: ["root"], beforeOrAt: time(2.5)) == .integer(2))
    }
}
