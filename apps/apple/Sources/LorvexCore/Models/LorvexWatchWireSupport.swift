import CoreFoundation
import Foundation
import LorvexDomain
import LorvexStore

/// Strict wire-contract failures for the Watch command and replica protocols.
public enum LorvexWatchWireError: Error, Equatable, LocalizedError, Sendable {
  case invalidJSON
  case invalidObject(String)
  case unexpectedKeys(String)
  case missingOrInvalidField(String)
  case unsupportedProtocolVersion(Int)
  case checksumMismatch

  public var errorDescription: String? {
    switch self {
    case .invalidJSON: "The Watch payload is not valid JSON."
    case .invalidObject(let name): "The Watch payload contains an invalid \(name) object."
    case .unexpectedKeys(let name): "The Watch payload contains unexpected \(name) keys."
    case .missingOrInvalidField(let field): "The Watch payload has an invalid \(field) field."
    case .unsupportedProtocolVersion(let version):
      "Watch protocol version \(version) is not supported."
    case .checksumMismatch: "The Watch payload checksum does not match its contents."
    }
  }
}

/// Shared helpers for the phone↔watch wire protocols (command journal, replica
/// snapshot). The enum is public so both endpoints of the wire — the phone-side
/// publisher in `LorvexMobile` and the watch-side journal in `LorvexWatch` —
/// validate identities with the same canonical byte check; the parsing helpers
/// stay internal to this module's wire decoding.
public enum LorvexWatchWire {
  /// True when `value` is exactly a canonical hyphenated lowercase UUID —
  /// the only byte shape Lorvex wire identities ever use. Uppercase,
  /// unhyphenated, braced, and `urn:uuid:` forms are rejected.
  public static func isCanonicalUUID(_ value: String) -> Bool {
    SyncEntityId.isCanonicalUuid(value)
  }

  static func object(from data: Data, name: String) throws -> [String: Any] {
    guard data.count <= 4 * 1024 * 1024,
      let value = try? JSONSerialization.jsonObject(with: data),
      let object = value as? [String: Any]
    else { throw LorvexWatchWireError.invalidJSON }
    return object
  }

  static func requireExactKeys(
    _ object: [String: Any], _ keys: Set<String>, name: String
  ) throws {
    guard Set(object.keys) == keys else {
      throw LorvexWatchWireError.unexpectedKeys(name)
    }
  }

  static func string(_ object: [String: Any], _ key: String) throws -> String {
    guard let value = object[key] as? String else {
      throw LorvexWatchWireError.missingOrInvalidField(key)
    }
    return value
  }

  static func optionalString(_ object: [String: Any], _ key: String) throws -> String? {
    guard let value = object[key] else {
      throw LorvexWatchWireError.missingOrInvalidField(key)
    }
    if value is NSNull { return nil }
    guard let string = value as? String else {
      throw LorvexWatchWireError.missingOrInvalidField(key)
    }
    return string
  }

  static func integer(_ object: [String: Any], _ key: String) throws -> Int64 {
    guard let number = object[key] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else { throw LorvexWatchWireError.missingOrInvalidField(key) }
    let type = String(cString: number.objCType)
    guard type != "f", type != "d" else {
      throw LorvexWatchWireError.missingOrInvalidField(key)
    }
    return number.int64Value
  }

  static func canonicalUUID(_ value: String, field: String) throws -> String {
    guard case .success(let parsed) = EntityID.parseIDWithSentinel(
      value, field: field, sentinel: nil), parsed == value
    else { throw LorvexWatchWireError.missingOrInvalidField(field) }
    return parsed
  }

  static func canonicalTimestamp(_ value: String, field: String) throws -> String {
    guard let parsed = SyncTimestamp.parse(value), parsed.asString == value else {
      throw LorvexWatchWireError.missingOrInvalidField(field)
    }
    return value
  }

  static func canonicalDate(_ value: String, field: String) throws -> String {
    guard IsoDate.parse(value)?.canonicalString == value else {
      throw LorvexWatchWireError.missingOrInvalidField(field)
    }
    return value
  }

  static func checksum(_ object: [String: Any]) throws -> String {
    Sha256Checksum.hexDigest(try jsonData(object))
  }

  static func requireChecksumShape(_ value: String) throws {
    guard value.utf8.count == 64,
      value.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
    else { throw LorvexWatchWireError.missingOrInvalidField("payload_checksum") }
  }

  static func jsonData(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw LorvexWatchWireError.invalidJSON
    }
    do {
      return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    } catch {
      throw LorvexWatchWireError.invalidJSON
    }
  }
}
