import Foundation

/// Errors surfaced by the SQLite-backed repositories in this module.
///
/// Distinct from GRDB's `DatabaseError` (which propagates as-is): these cases
/// model semantic outcomes the storage layer commits to as part of its public
/// contract.
public enum StoreError: Error, Sendable, Equatable {
  /// LWW gate rejected a write because the supplied `version` was not
  /// strictly greater than the row's current `version`.
  ///
  /// `entity` is the canonical entity-kind string (e.g. `"list"`), `id` is
  /// the row's primary-key string.
  case staleVersion(entity: String, id: String)

  /// A row carried a valid version that the caller's attempted stamp did not
  /// strictly supersede. Unlike ``staleVersion(entity:id:)``, this case carries
  /// the observed floor so composite-key and already-deleted rows can be
  /// retried without an unreliable `(table, primary-key)` lookup.
  case versionSuperseded(
    entityType: String,
    entityId: String,
    attemptedVersion: String,
    existingVersion: String)

  /// Lookup-by-id target row does not exist. Distinguished from
  /// `.staleVersion` so callers can render the canonical "missing" vs
  /// "stale" feedback.
  case notFound(entity: String, id: String)

  /// Input rejected at the repository entry before SQL ran. Carries the
  /// user-facing message.
  case validation(String)

  /// JSON (de)serialization failed, or a value had the wrong JSON shape
  /// (e.g. a recurrence rule that is not a JSON object).
  case serialization(String)

  /// Internal invariant violated — a contract between caller and repo
  /// (e.g. `status` update missing typed `beforeStatus`, or a persisted
  /// row carrying a non-canonical enum value).
  case invariant(String)
}

extension StoreError: CustomStringConvertible, LocalizedError {
  /// Human-readable message for each case. `.validation` carries an
  /// already-user-facing string and is surfaced verbatim. Conforming to both
  /// `CustomStringConvertible` and `LocalizedError` means `String(describing:)`
  /// *and* `localizedDescription` (the latter used by the MCP error bridge)
  /// yield this message instead of the opaque "StoreError error N" default.
  public var description: String {
    switch self {
    case .staleVersion(let entity, let id):
      return "This \(entity) ('\(id)') was changed by another update; reload and try again."
    case .versionSuperseded(let entityType, let entityId, let attempted, let existing):
      return
        "This \(entityType) ('\(entityId)') was changed by another update "
        + "(attempted \(attempted), existing \(existing)); reload and try again."
    case .notFound(let entity, let id):
      return "\(entity) '\(id)' was not found."
    case .validation(let message):
      return message
    case .serialization(let message):
      return "Serialization error: \(message)"
    case .invariant(let message):
      return "Internal invariant violated: \(message)"
    }
  }

  public var errorDescription: String? { description }
}
