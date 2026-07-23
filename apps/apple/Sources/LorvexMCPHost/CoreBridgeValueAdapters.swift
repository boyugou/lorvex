import Foundation
import MCP

extension CoreBridgeClient {
  static func anyValue(from value: Any?) -> Value {
    switch value {
    case let value as String:
      return .string(value)
    // NSNumber must be classified before any `as Int` cast: a JSON `true`
    // arrives as a boolean NSNumber, which bridges to Int and would serialize
    // as 1 instead of true. Swift-native Int/Double/Bool also bridge to
    // NSNumber, so this one branch covers every numeric input.
    case let value as NSNumber:
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return .bool(value.boolValue)
      }
      if let intValue = value as? Int {
        return .int(intValue)
      }
      return .double(value.doubleValue)
    case let value as [String: Any]:
      return .object(value.mapValues(anyValue(from:)))
    case let value as [Any]:
      return .array(value.map(anyValue(from:)))
    case _ as NSNull, nil:
      return .null
    default:
      return .string(String(describing: value as Any))
    }
  }
}
