import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime

extension SwiftLorvexCoreService {

  /// Process-wide normal HLC generator state for one device/surface writer.
  ///
  /// Ordinary writes use `normalState`, which follows wall time and bounded peer
  /// observations. Its local-only trusted high-water is namespaced by the exact
  /// device suffix as well as the surface: a restored/cloned database whose
  /// install identity rotates starts a fresh normal clock instead of inheriting
  /// the old installation's bad wall clock.
  ///
  /// A transaction that must explicitly supersede a future-stamped row uses a
  /// separate detached lane. Its high-water is durable and device/surface scoped
  /// so two exceptional transactions can never mint the same HLC, while ordinary
  /// writes remain on the bounded normal lane and are never pinned to that future.
  final class HlcClock: @unchecked Sendable {
    private let lock = NSLock()
    private let normalState: HlcState
    private let surface: HlcSurface
    let deviceSuffix: String
    private var seededFallback = false

    init(deviceId: String, surface: HlcSurface) throws {
      let suffix = DeviceIdentity.deviceIdToHlcSuffix(deviceId, surface: surface)
      self.normalState = try HlcState(deviceSuffix: suffix)
      self.surface = surface
      self.deviceSuffix = suffix
    }

    var normalHighWaterKey: String {
      "hlc_highwater.normal.\(surface.rawValue).\(deviceSuffix)"
    }

    var detachedHighWaterKey: String {
      "hlc_highwater.detached.\(surface.rawValue).\(deviceSuffix)"
    }

    /// Refresh trusted lane high-waters from the active write transaction and
    /// return its transaction-scoped handle. This read happens for every write,
    /// not just process startup: another process using the same surface may have
    /// committed since this clock last ran.
    func makeTransactionHandle(_ db: Database) throws -> HlcTransactionHandle {
      try refreshHighWaters(db)
      let detachedRaw = try SyncCheckpoints.get(db, key: detachedHighWaterKey)
      let detached = try Self.parseHighWater(
        detachedRaw, key: detachedHighWaterKey, expectedSuffix: deviceSuffix)
      return HlcTransactionHandle(clock: self, detachedHighWater: detached)
    }

    /// Compatibility/test seam for callers that only need to seed the in-memory
    /// clock. Production writes use ``makeTransactionHandle(_:)`` so corruption
    /// in a trusted checkpoint fails closed instead of being swallowed.
    func seedIfNeeded(_ db: Database) {
      try? refreshHighWaters(db)
    }

    private func refreshHighWaters(_ db: Database) throws {
      let normalRaw = try SyncCheckpoints.get(db, key: normalHighWaterKey)
      let trustedNormal = try Self.parseHighWater(
        normalRaw, key: normalHighWaterKey, expectedSuffix: deviceSuffix)

      lock.lock()
      let needsFallback = !seededFallback && trustedNormal == nil
      lock.unlock()

      // A synced row suffix is forgeable, so this bootstrap source is bounded.
      // Only this exact device/surface suffix participates; retired identities
      // and other surfaces use per-row detached dominance if an edit needs it.
      let fallback = needsFallback ? try Self.maxLocalHlc(db, suffixes: [deviceSuffix]) : nil

      lock.lock()
      defer { lock.unlock() }
      if let trustedNormal {
        normalState.updateOnReceive(remote: trustedNormal, physicalMs: Self.nowMs())
      }
      if !seededFallback {
        if let fallback {
          normalState.updateOnReceive(
            remote: fallback, physicalMs: Self.nowMs(),
            maxForwardDriftMs: HlcState.maxInboundForwardDriftMs)
        }
        seededFallback = true
      }
    }

    private static func parseHighWater(
      _ raw: String?, key: String, expectedSuffix: String
    ) throws -> Hlc? {
      guard let raw else { return nil }
      do {
        let parsed = try Hlc.parseCanonical(raw)
        guard parsed.deviceSuffix == expectedSuffix else {
          throw HlcHighWaterError.invalidCheckpoint(key: key, value: raw)
        }
        return parsed
      } catch let error as HlcHighWaterError {
        throw error
      } catch {
        throw HlcHighWaterError.invalidCheckpoint(key: key, value: raw)
      }
    }

    /// Direct normal-lane mint retained for deterministic clock tests. Durable
    /// production writes mint through `HlcTransactionHandle`.
    func generate() -> Hlc {
      generateNormal()
    }

    func generateNormal() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      return normalState.generate(withPhysicalMs: Self.nowMs())
    }

    /// Observe an inbound peer version on the normal lane with bounded drift.
    /// The envelope keeps its full version for LWW; only future local normal
    /// mints are protected from fleet-wide clock pinning.
    func observePeerEnvelope(_ remote: Hlc) {
      lock.lock()
      defer { lock.unlock() }
      normalState.updateOnReceive(
        remote: remote, physicalMs: Self.nowMs(),
        maxForwardDriftMs: HlcState.maxInboundForwardDriftMs)
    }

    /// Apply-time merge HLCs are derived from peer-controlled participant
    /// versions, so observing them is bounded just like a peer envelope.
    func reserveAfterDeterministicMerge(_ hlc: Hlc) -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      normalState.updateOnReceive(
        remote: hlc, physicalMs: Self.nowMs(),
        maxForwardDriftMs: HlcState.maxInboundForwardDriftMs)
      return normalState.generate(withPhysicalMs: Self.nowMs())
    }

    static func nowMs() -> UInt64 {
      if let override = SwiftLorvexCoreService.hlcPhysicalNowMsForTesting {
        return override()
      }
      let t = Date().timeIntervalSince1970
      return t < 0 ? 0 : UInt64(t * 1000)
    }

    /// Version columns eligible for the one-time, exact-local-suffix bootstrap
    /// when no trusted high-water exists. This is deliberately not a catalog of
    /// every HLC-shaped diagnostic/control column: pending remote records and
    /// loser-only diagnostics must not seed a writer clock. Schema-wide HLC
    /// guard coverage lives in `SyncControlSchemaIntegrityTests`.
    static let hlcBearingTables: [(table: String, column: String)] = [
      ("audit_retention_account_state", "policy_version"),
      ("audit_retention_binding", "unbound_policy_version"),
      ("calendar_events", "content_version"),
      ("calendar_events", "recurrence_generation"),
      ("calendar_events", "recurrence_topology_version"),
      ("calendar_events", "version"),
      ("calendar_series_cutovers", "version"),
      ("current_focus", "version"),
      ("daily_reviews", "version"),
      ("focus_schedule", "version"),
      ("habit_completions", "version"),
      ("habit_reminder_policies", "version"),
      ("habits", "version"),
      ("lists", "version"),
      ("memories", "version"),
      ("preferences", "version"),
      ("sync_conflict_log", "winner_version"),
      ("sync_entity_redirects", "version"),
      ("sync_generation_snapshot_compacted_tombstones", "version"),
      ("sync_generation_snapshot_tombstone_receipts", "version"),
      ("sync_outbox", "version"),
      ("sync_payload_shadow", "base_version"),
      ("sync_quarantine_blocklist", "version"),
      ("sync_tombstones", "version"),
      ("tags", "version"),
      ("task_calendar_event_links", "version"),
      ("task_checklist_items", "version"),
      ("task_dependencies", "version"),
      ("task_reminders", "version"),
      ("task_tags", "version"),
      ("tasks", "archive_version"),
      ("tasks", "content_version"),
      ("tasks", "lifecycle_version"),
      ("tasks", "schedule_version"),
      ("tasks", "spawned_from_version"),
      ("tasks", "version"),
    ]

    static func maxLocalHlc(_ db: Database, suffixes: [String]) throws -> Hlc? {
      var best: Hlc?
      for suffix in suffixes {
        for entry in hlcBearingTables {
          // Filter to the exact canonical fixed-width layout in SQL before
          // taking MAX. Otherwise one parseable-but-noncanonical raw value that
          // sorts above the table's canonical values would hide the real local
          // floor even though the Swift guard correctly refuses to trust it.
          let sql = """
            SELECT MAX(\(entry.column)) FROM \(entry.table)
            WHERE length(\(entry.column)) = 35
              AND substr(\(entry.column), 14, 1) = '_'
              AND substr(\(entry.column), 19, 1) = '_'
              AND substr(\(entry.column), 1, 13) NOT GLOB '*[^0-9]*'
              AND substr(\(entry.column), 15, 4) NOT GLOB '*[^0-9]*'
              AND substr(\(entry.column), 20, 16) = ? COLLATE BINARY
            """
          guard let raw = try String.fetchOne(db, sql: sql, arguments: [suffix]),
            !raw.isEmpty,
            let hlc = try? Hlc.parseCanonical(raw)
          else { continue }
          best = best.map { max($0, hlc) } ?? hlc
        }
      }
      return best
    }

    /// Highest canonical HLC currently represented anywhere in the local sync
    /// state, regardless of author. Used only after an explicit local mutation
    /// has already lost an LWW gate: seeding that transaction's detached retry
    /// past the complete local ceiling lets a multi-row edit supersede every
    /// heterogeneous future floor in one replay. It never advances the normal
    /// wall-time lane.
    static func maxAnyLocalHlc(_ db: Database) throws -> Hlc? {
      var best: Hlc?
      for entry in authoritativeRetryHlcTables {
        let sql = "SELECT MAX(\(entry.column)) FROM \(entry.table)"
        guard let raw = try String.fetchOne(db, sql: sql), !raw.isEmpty else { continue }
        let parsed: Hlc
        do {
          parsed = try Hlc.parseCanonical(raw)
        } catch let error as HlcHighWaterError {
          throw error
        } catch {
          throw HlcHighWaterError.invalidStoredVersion(
            table: entry.table, column: entry.column, value: raw)
        }
        best = best.map { max($0, parsed) } ?? parsed
      }
      return best
    }

    /// State that can still win or block a real LWW decision. Historical
    /// conflict diagnostics, transport projections, and the quarantine
    /// blocklist are intentionally not global retry floors: a stale peer value
    /// recorded there must not pin an unrelated explicit edit. Canonical rows,
    /// tombstones, and forward-compat payload shadows remain authoritative.
    /// Same-identity quarantine handling remains a per-entity reconciliation
    /// concern.
    private static let authoritativeRetryHlcTables = hlcBearingTables.filter {
      $0.table != "sync_conflict_log"
        && $0.table != "sync_outbox"
        && $0.table != "sync_quarantine_blocklist"
    }
  }

  enum HlcHighWaterError: Error, Equatable, CustomStringConvertible {
    case invalidCheckpoint(key: String, value: String)
    case invalidStoredVersion(table: String, column: String, value: String)
    case unrecoverableFloor(value: String)

    var description: String {
      switch self {
      case .invalidCheckpoint(let key, let value):
        return "invalid trusted HLC high-water checkpoint \(key): \(value)"
      case .invalidStoredVersion(let table, let column, let value):
        return "invalid stored HLC in \(table).\(column): \(value)"
      case .unrecoverableFloor(let value):
        return "cannot mint a strictly ordered local HLC beyond \(value)"
      }
    }
  }
}
