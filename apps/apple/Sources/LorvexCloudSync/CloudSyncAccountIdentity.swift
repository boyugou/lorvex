@preconcurrency import CloudKit
import CryptoKit
import Foundation
import LorvexCore

/// Reads the opaque identity of the iCloud account currently signed in on THIS
/// device — the CloudKit current-user record-ID hash for the app's container.
/// Used only to detect a switch to a DIFFERENT account so the account-change
/// handler can suppress backfilling this device's data into a stranger's zone.
///
/// There is a SINGLE identity format. FAIL-CLOSED: when the current-user record
/// cannot be read this cycle (CloudKit unreachable, signed out, indeterminate),
/// the identity is `nil` — "unknown" — and the caller skips the cycle rather
/// than syncing or persisting any alternate identity.
public protocol CloudKitAccountIdentifying: Sendable {
  /// The identity of the account signed in right now, or `nil` when it cannot be
  /// determined this cycle (no account signed in, or the CloudKit current-user
  /// record lookup failed). The value is an opaque SHA-256 that is never sent
  /// over the wire; only equality matters.
  func currentAccountIdentifier() async -> String?
}

/// Production identifier backed by CloudKit's current-user record ID for the
/// app's container. The returned identity is an opaque SHA-256 of that record
/// name; it is never sent over the wire and only equality matters.
///
/// FAIL-CLOSED, single format: when the current-user record lookup fails
/// (CloudKit unreachable, signed out, indeterminate), `currentAccountIdentifier()`
/// returns `nil` — "unknown" — so the caller skips the cycle instead of syncing
/// or persisting any alternate identity. There is deliberately no offline
/// fallback identity: a rare transient sync pause is traded for a single,
/// easy-to-reason-about identity format.
public struct CloudKitUserRecordAccountIdentifier: CloudKitAccountIdentifying {
  /// Reads the container's current-user record name. Production supplies the
  /// `CKContainer(...).userRecordID().recordName` lookup; tests inject a closure
  /// to exercise the hashing / `nil`-on-throw logic without touching CloudKit.
  private let recordNameProvider: @Sendable () async throws -> String

  public init(
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier
  ) {
    self.init(recordNameProvider: {
      try await CKContainer(identifier: containerIdentifier).userRecordID().recordName
    })
  }

  public init(recordNameProvider: @escaping @Sendable () async throws -> String) {
    self.recordNameProvider = recordNameProvider
  }

  public func currentAccountIdentifier() async -> String? {
    guard
      let recordName = try? await recordNameProvider(),
      !recordName.isEmpty
    else { return nil }
    return Self.hash(Data("cloudkit-user-record-id:\(recordName)".utf8))
  }

  private static func hash(_ data: Data) -> String {
    CloudSyncHex.lowercase(SHA256.hash(data: data), capacity: SHA256.Digest.byteCount)
  }
}

/// Persists the fingerprint of the iCloud account this device last backfilled
/// into, so a later `CKAccountChanged` can tell a same-account re-auth (safe to
/// re-backfill) from a switch to a different account (must NOT auto-backfill). It
/// MUST survive app relaunches — a switch that happens while the app is closed is
/// the primary case the account-change guard defends against. `save` never takes
/// `nil`: a sign-out must not erase the memory of the last account.
///
/// FAIL-CLOSED contract: `save` returns only once the fingerprint is durably on
/// disk and a readback verified it, and throws otherwise; `load` returns `nil`
/// only for genuinely absent state (nothing ever recorded) and throws when a
/// recorded fingerprint exists but cannot be read or decoded. Callers halt on
/// either throw — proceeding on an unverified or unknown binding is what lets a
/// later account switch masquerade as a first run.
public protocol CloudSyncAccountIdentityStoring: Sendable {
  func loadLastAccountIdentifier() async throws -> String?
  func saveLastAccountIdentifier(_ identifier: String) async throws
}

/// File-backed ``CloudSyncAccountIdentityStoring`` writing a single small file in
/// the backup-eligible CloudSync safety-state directory.
/// Survives relaunches; scoped per container by the directory the factory picks.
/// Writes go through ``CloudSyncDurableStateFile`` (stage → fsync → rename →
/// verified readback), so a returned save proves the fingerprint is durable.
public actor FileCloudSyncAccountIdentityStore: CloudSyncAccountIdentityStoring {
  private static let fileName = "account-identity.txt"
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public func loadLastAccountIdentifier() async throws -> String? {
    let url = directory.appendingPathComponent(Self.fileName)
    guard let data = try CloudSyncDurableStateFile.readIfPresent(at: url) else { return nil }
    guard let raw = String(data: data, encoding: .utf8) else {
      throw CloudSyncDurableStateError.unreadable("account identity is not valid UTF-8")
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      // A recorded identity is never empty (`save` takes a non-empty
      // fingerprint), so an empty file is corruption — not a first run.
      throw CloudSyncDurableStateError.unreadable("account identity file is empty")
    }
    return trimmed
  }

  public func saveLastAccountIdentifier(_ identifier: String) async throws {
    try CloudSyncDurableStateFile.write(
      Data(identifier.utf8), to: directory.appendingPathComponent(Self.fileName))
  }
}
