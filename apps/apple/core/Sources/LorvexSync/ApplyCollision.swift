import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import Synchronization

/// A cheap apply-time backstop for a same-suffix / different-`device_id` peer.
///
/// A cloned database (iCloud restore, filesystem copy, backup-and-rename) would
/// otherwise let two live installs share one `sync_checkpoints.device_id` — the
/// catastrophic-but-silent case. That is prevented at the source by the open-time
/// install-identity reconciliation (``SwiftLorvexCoreService`` resolves the
/// in-DB id against a backup-excluded install marker and ROTATES a restored/cloned
/// DB to a fresh id), so a genuine clone never reaches this pipeline sharing an id.
///
/// What remains for this check is the residual case where two DISTINCT full
/// device ids derive the SAME 64-bit HLC suffix — an astronomically-unlikely
/// SHA-256 collision, not a clone. It surfaces that via one throttled `error_logs`
/// row (a process-global flag keeps a sync batch from drowning the diagnostics
/// feed) and is otherwise best-effort and non-throwing.
enum ApplyCollision {
  /// Process-global logged-once guard: a colliding peer pair would otherwise
  /// produce one `error_logs` row per envelope during a sync batch.
  private static let loggedFlag = Mutex(false)

  /// Compare the incoming envelope's `device_id` against the local
  /// `sync_checkpoints.device_id` when their HLC suffixes match. Since the
  /// open-time reconciliation rotates a restored/cloned DB before its writes ever
  /// sync, a surviving suffix match with a mismatched full id is the residual
  /// hash-collision case, not a clone. Writes one loud `error_logs` entry and
  /// sets the guard so the rest of the batch stays quiet. Best-effort: never throws.
  static func checkDeviceIdentityCollision(_ db: Database, envelope: SyncEnvelope) {
    // Cheap short-circuit: if we already logged, skip the DB read.
    if loggedFlag.withLock({ $0 }) { return }

    guard let (localDeviceId, localSuffixes) = readLocalDeviceIdentity(db) else {
      return
    }
    let envelopeSuffix = envelope.version.deviceSuffix
    guard shouldReportCollision(
      localDeviceId: localDeviceId, localSuffixes: localSuffixes,
      envelopeDeviceId: envelope.deviceId, envelopeSuffix: envelopeSuffix,
      envelopeDerivedSuffixes: HlcSurface.allSurfaces.map {
        DeviceIdentity.deviceIdToHlcSuffix(envelope.deviceId, surface: $0)
      })
    else { return }

    // Single-log race guard: exactly one caller wins the flip.
    let alreadyLogged = loggedFlag.withLock { flag -> Bool in
      if flag { return true }
      flag = true
      return false
    }
    if alreadyLogged { return }

    let details =
      "device_suffix=\(envelopeSuffix) is shared by at least two peers. "
      + "local device_id=\(localDeviceId) but envelope carries device_id=\(envelope.deviceId). "
      + "Both full device ids independently derive this suffix, so this is a "
      + "64-bit suffix collision. LWW ties are unsafe until one install rotates "
      + "its device identity."
    // The error_logs row IS the entire observable effect of the detector, so
    // unlike the dropped breadcrumbs elsewhere in this target it is preserved.
    // Route through the shared writer so the redact-then-truncate contract
    // (strip bearer tokens / keys / emails / home paths, bound length) applies
    // uniformly. Best-effort: a failed write must not eclipse the apply path.
    ErrorLog.appendBestEffort(
      db, source: "sync.apply.device_collision",
      message: "HLC device_suffix collision between peers — sync LWW is unsafe",
      details: details, level: "error")
  }

  /// A generation snapshot legitimately republishes a stored HLC using the
  /// rebuilding device's transport `device_id`; that wrapper is not the HLC's
  /// original author and must not look like a collision. Report only when the
  /// suffix is self-consistent with both distinct full ids.
  static func shouldReportCollision(
    localDeviceId: String, localSuffixes: [String],
    envelopeDeviceId: String, envelopeSuffix: String,
    envelopeDerivedSuffixes: [String]
  ) -> Bool {
    localDeviceId != envelopeDeviceId
      && localSuffixes.contains(envelopeSuffix)
      && envelopeDerivedSuffixes.contains(envelopeSuffix)
  }

  /// Read the local `sync_checkpoints.device_id` and the full set of HLC
  /// suffixes this device can emit — one per ``HlcSurface``.
  static func readLocalDeviceIdentity(_ db: Database) -> (String, [String])? {
    guard
      let deviceId = try? String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'device_id'"),
      !deviceId.isEmpty
    else {
      return nil
    }
    let suffixes = HlcSurface.allSurfaces.map {
      DeviceIdentity.deviceIdToHlcSuffix(deviceId, surface: $0)
    }
    return (deviceId, suffixes)
  }

  /// Reset the once-per-process guard. Test-only.
  static func resetGuardForTesting() {
    loggedFlag.withLock { $0 = false }
  }
}
