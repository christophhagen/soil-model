import Foundation
import Soil
import SoilModel

enum Priority: Int, ValueConvertible {
    case low = 0
    case high = 1
}

struct Address: Codable, Equatable, ValueConvertible {
    var street: String
    var city: String
    var tags: [String] = []
    var moved: Date? = nil
}

final class Person: Model {

    @Property
    var name: String

    @Property
    var age: Int = 18

    @Property("nick")
    var nickname: String?

    @Property
    var priority: Priority = .low

    @Property
    var address: Address?

    @Reference
    var partner: Person?

    @ReferenceList
    var friends: [Person]

    @Reference
    var pet: Animal?

    @ReferenceList
    var pets: [Animal]
}

class Animal: Model {

    @Property
    var name: String
}

final class Dog: Animal {

    override class var modelId: String { "dog" }

    @Property
    var breed: String
}

final class DuplicateKeys: Model {

    @Property
    var value: Int

    @Property("value")
    var other: String
}
