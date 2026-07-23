import GRDB
import LorvexDomain
import enum LorvexStore.DeviceIdentity

/// Device-identity runtime surface.
///
/// The canonical byte-level implementation lives in ``LorvexStore`` — its
/// `DeviceIdentity.deviceIdToHlcSuffix` is the byte-faithful HLC-suffix
/// derivation (SHA-256 of dash-stripped lowercase device_id || "|" || surface,
/// first 8 bytes as 16 lowercase hex chars). The Database-backed device-id
/// seeder is `LorvexStore.SyncCheckpoints.getOrCreateDeviceId` (a single
/// `INSERT OR IGNORE` claim + readback).
///
/// This runtime surface re-exports the store enum verbatim rather than
/// re-deriving the hash here — a second copy would be exactly the divergence
/// risk that re-export avoids. `LorvexStore` is the authoritative source.
public typealias DeviceIdentity = LorvexStore.DeviceIdentity

extension DeviceIdentity {
  /// Read-or-generate-and-persist the stable device id from
  /// `sync_checkpoints[device_id]`. Forwards to the Database-backed
  /// `LorvexStore.SyncCheckpoints.getOrCreateDeviceId` (a single
  /// `INSERT OR IGNORE` claim + readback). This connection-backed path is the
  /// one sync envelopes drive.
  @discardableResult
  public static func getOrCreateDeviceId(
    _ db: Database, generate: () -> String = { EntityID.newEntityIDString() }
  ) throws -> String {
    try SyncCheckpoints.getOrCreateDeviceId(db, generate: generate)
  }
}
