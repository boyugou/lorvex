import Foundation
import LorvexDomain

extension SwiftLorvexCoreService {
  /// Validate a parent-owned collection's embedded sync identities before any
  /// local row or outbox envelope is written. These collections use soft refs,
  /// so SQLite cannot reject malformed IDs; without this guard a local import
  /// could emit an envelope every peer correctly refuses at its trust boundary.
  static func canonicalImportedEntityIDs(
    _ values: [String], kind: EntityKind, field: String
  ) throws -> [String] {
    var seen = Set<String>()
    for (index, value) in values.enumerated() {
      guard case .success = SyncEntityId.validateForKind(kind, value) else {
        throw LorvexCoreError.unsupportedOperation(
          "\(field)[\(index)] must be a canonical \(kind.asString) identity.")
      }
      guard seen.insert(value).inserted else {
        throw LorvexCoreError.unsupportedOperation(
          "\(field) must not contain duplicate identity '\(value)'.")
      }
    }
    return values
  }

  /// Parse an external/import timestamp and persist the single canonical sync
  /// representation. Imports may accept RFC 3339 spellings such as a missing
  /// fractional component, but no noncanonical spelling may reach SQLite and
  /// subsequently fail the final outbox payload contract.
  static func canonicalImportTimestamp(
    _ raw: String?, field: String, fallback: String
  ) throws -> String {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return fallback
    }
    guard let parsed = SyncTimestamp.parse(value) else {
      throw LorvexCoreError.unsupportedOperation("\(field) must be a sync timestamp.")
    }
    return parsed.asString
  }

  /// Optional counterpart that preserves an absent/blank imported value while
  /// canonicalizing every present timestamp.
  static func canonicalOptionalImportTimestamp(
    _ raw: String?, field: String
  ) throws -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    guard let parsed = SyncTimestamp.parse(value) else {
      throw LorvexCoreError.unsupportedOperation("\(field) must be a sync timestamp.")
    }
    return parsed.asString
  }

  /// Required counterpart for timestamp fields whose absence is itself invalid.
  static func canonicalRequiredImportTimestamp(
    _ raw: String, field: String
  ) throws -> String {
    guard let value = try canonicalOptionalImportTimestamp(raw, field: field) else {
      throw LorvexCoreError.unsupportedOperation("A \(field) is required.")
    }
    return value
  }
}
