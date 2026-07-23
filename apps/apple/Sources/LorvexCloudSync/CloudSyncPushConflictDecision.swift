import Foundation
import LorvexDomain

/// The branch a contested CloudKit push must take when CloudKit rejects a save
/// with `serverRecordChanged` (the server's change tag is newer than the one we
/// supplied).
///
/// CloudKit's change-tag check is a write barrier, not the conflict authority:
/// the engine's HLC last-writer-wins is. So a `serverRecordChanged` rejection is
/// re-resolved here by comparing the pushed record's `version` HLC against the
/// server record's `version` HLC, and the outcome decides what happens to the
/// contested record and its outbox row.
public enum CloudSyncPushConflictDecision: Equatable, Sendable {
  /// Local HLC is strictly newer. Re-stamp the local field values onto the
  /// server's returned record instance (which carries the current change tag)
  /// and re-save it, so the engine's winner reaches the server. Confirm the
  /// outbox row once the re-save lands.
  case localWinsResaveOntoServer

  /// Server HLC is strictly newer than ours — our push lost LWW. Do NOT
  /// overwrite the server. Confirm the outbox row and apply the server's record
  /// locally so this device also holds the winning version; the engine's
  /// inbound apply is idempotent, so applying a record we may already have is
  /// safe.
  case serverWinsConfirmAndApply

  /// The two HLCs are equal — both peers already agree on the version, so the
  /// caller must next prove the complete wire fields are byte-identical. Only
  /// then may it confirm the outbox row without re-saving or re-applying.
  /// Equal-version/different-content records violate HLC mutation identity and
  /// are reclaimed rather than silently confirmed.
  case equalConfirm

  /// The local HLC is canonical, but the exact server slot has no canonical
  /// ordering key. Core must re-author the local intent at a fresh successor;
  /// transport must never reclaim the slot under the old HLC.
  case corruptServerSlot
}

/// Re-resolve a `serverRecordChanged` rejection by HLC comparison.
///
/// `localVersion` / `serverVersion` are the canonical HLC strings carried in the
/// `version` field of the pushed record and the server's returned record. Both
/// must parse and round-trip byte-identically through ``Hlc/description`` before
/// they participate in ordering. Canonical values are ordered with ``Hlc``'s `Comparable` —
/// the same total order ``Merge/resolveLww`` is built on, so the push path and
/// the inbound apply path agree on which version wins:
///
/// - `server > local` → ``serverWinsConfirmAndApply``
/// - `local > server` → ``localWinsResaveOntoServer``
/// - `local == server` → ``equalConfirm``
///
/// An invalid local value cannot claim authority and falls back to the server
/// path. An absent/noncanonical server value is instead a typed corrupt slot:
/// it has no ordering key that can safely win, but transport still must not
/// overwrite it with the old local HLC. Core resolves that outcome by minting a
/// fresh successor before the server change tag is cached.
public func resolveCloudSyncPushConflict(
  localVersion: String, serverVersion: String
) -> CloudSyncPushConflictDecision {
  guard let local = try? Hlc.parseCanonical(localVersion) else {
    return .serverWinsConfirmAndApply
  }
  guard let server = try? Hlc.parseCanonical(serverVersion) else {
    return .corruptServerSlot
  }
  if server > local { return .serverWinsConfirmAndApply }
  if local > server { return .localWinsResaveOntoServer }
  return .equalConfirm
}
