#if canImport(SwiftUI)
import SwiftUI

/**
 A property wrapper to fetch all active instances of a model in a SwiftUI view.

 The context is read from the environment, which must be provided using `.environment(context)`:

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

 The view is updated when instances are created or deleted, and when properties used for filtering or sorting change.
 */
@MainActor
@propertyWrapper
public struct Query<M: Model>: DynamicProperty {

    @Environment(ModelContext.self)
    private var context

    private let filter: (M) -> Bool

    private let areInIncreasingOrder: ((M, M) -> Bool)?

    /**
     Create a query.
     - Parameter filter: The filter to select instances
     */
    public init(filter: @escaping (M) -> Bool = { _ in true }) {
        self.filter = filter
        self.areInIncreasingOrder = nil
    }

    /**
     Create a sorted query.
     - Parameter filter: The filter to select instances
     - Parameter sortBy: The key path of the property used for sorting
     - Parameter order: The sort order
     */
    public init<Value: Comparable>(filter: @escaping (M) -> Bool = { _ in true }, sortBy keyPath: KeyPath<M, Value>, order: SortOrder = .forward) {
        self.filter = filter
        self.areInIncreasingOrder = { lhs, rhs in
            switch order {
            case .forward: lhs[keyPath: keyPath] < rhs[keyPath: keyPath]
            case .reverse: lhs[keyPath: keyPath] > rhs[keyPath: keyPath]
            }
        }
    }

    /// The instances matching the query
    public var wrappedValue: [M] {
        let instances = context.all(M.self, where: filter)
        guard let areInIncreasingOrder else {
            return instances
        }
        return instances.sorted(by: areInIncreasingOrder)
    }
}
#endif
