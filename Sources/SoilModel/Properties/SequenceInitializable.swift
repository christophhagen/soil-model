/**
 A collection that can be created from a sequence.

 Conformance to this protocol is required for collections used with ``ReferenceList``.
 */
public protocol SequenceInitializable: Collection {

    init<S: Sequence>(_ sequence: S) where S.Element == Element
}

extension Array: SequenceInitializable { }

extension ContiguousArray: SequenceInitializable { }

extension Set: SequenceInitializable { }
