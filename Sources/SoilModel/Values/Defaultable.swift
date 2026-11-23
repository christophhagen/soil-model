import Foundation

/**
 A type that provides a default value.

 Properties of `Defaultable` types don't need an explicit default value:

 ```swift
 @Property
 var count: Int // Defaults to `0`
 ```
 */
public protocol Defaultable {

    /// The default value used when no value is stored
    static var `default`: Self { get }
}

extension Int: Defaultable { public static var `default`: Int { 0 } }
extension Int8: Defaultable { public static var `default`: Int8 { 0 } }
extension Int16: Defaultable { public static var `default`: Int16 { 0 } }
extension Int32: Defaultable { public static var `default`: Int32 { 0 } }
extension Int64: Defaultable { public static var `default`: Int64 { 0 } }
extension UInt: Defaultable { public static var `default`: UInt { 0 } }
extension UInt8: Defaultable { public static var `default`: UInt8 { 0 } }
extension UInt16: Defaultable { public static var `default`: UInt16 { 0 } }
extension UInt32: Defaultable { public static var `default`: UInt32 { 0 } }
extension UInt64: Defaultable { public static var `default`: UInt64 { 0 } }
extension Double: Defaultable { public static var `default`: Double { 0 } }
extension Float: Defaultable { public static var `default`: Float { 0 } }
extension Bool: Defaultable { public static var `default`: Bool { false } }
extension String: Defaultable { public static var `default`: String { "" } }
extension Data: Defaultable { public static var `default`: Data { Data() } }
extension Array: Defaultable { public static var `default`: Array { [] } }
extension Set: Defaultable { public static var `default`: Set { [] } }
extension Dictionary: Defaultable { public static var `default`: Dictionary { [:] } }
