import os

/// A stable, privacy-safe `OSSignposter` vocabulary for Lorvex's load-bearing
/// runtime phases, so Instruments (and MetricKit signpost metrics) can attribute
/// a real-device hang, disk-write, or energy sample to a named product
/// operation instead of an anonymous stack frame.
///
/// Every interval is emitted on one process-wide ``signposter``. The vocabulary
/// is deliberately small and its ``Phase/label`` strings are frozen so a saved
/// Instruments template keeps matching across refactors. Interval metadata must
/// stay restricted to bounded counts and result categories — never
/// user-authored text, record ids, titles, file paths, or calendar contents.
///
/// Overhead: when no tool is recording, `OSSignposter` is disabled and
/// ``begin(_:)`` / ``end(_:)`` are near-free, so this instrumentation is safe to
/// leave compiled into Release. Callers must balance every ``begin(_:)`` with an
/// ``end(_:)`` on success, error, and cancellation (use `defer`, or the
/// ``withInterval(_:_:)`` helpers, which end on any exit).
public enum LorvexSignpost {
  /// The instrumented phases. Case-per-phase keeps the set enumerable (a
  /// stability test iterates ``allCases``); the frozen ``label`` strings follow
  /// the audit's `domain.phase` scheme.
  public enum Phase: Sendable, Hashable, CaseIterable {
    /// `SwiftLorvexCoreService` opening — and, on first open, migrating — the
    /// on-disk core store.
    case databaseOpen
    /// One GRDB read transaction on the core store.
    case databaseRead
    /// One GRDB write transaction on the core store.
    case databaseWrite
    /// One CloudKit draining cycle (subscription-gated push, pull, and apply)
    /// run off the main actor.
    case cloudSync
    /// One EventKit ingest window: fetch provider events and upsert the local
    /// occupancy mirror.
    case eventKitIngest
    /// Replacing a Core Spotlight index set (task index or content index).
    case spotlightReplace
    /// The refresh fan-out's task + habit reminder/notification re-plan pass.
    case notificationsReplace
    /// One full refresh fan-out (`performRefresh`) — the composite that loads the
    /// UI snapshot and republishes the system surfaces.
    case refreshTotal

    /// The `StaticString` the OS signpost machinery records. Kept a compile-time
    /// literal because the signpost tooling registers interval names statically.
    var signpostName: StaticString {
      switch self {
      case .databaseOpen: return "database.open"
      case .databaseRead: return "database.read"
      case .databaseWrite: return "database.write"
      case .cloudSync: return "cloud.sync"
      case .eventKitIngest: return "eventkit.ingest"
      case .spotlightReplace: return "spotlight.replace"
      case .notificationsReplace: return "notifications.replace"
      case .refreshTotal: return "refresh.total"
      }
    }

    /// The frozen string label, derived from ``signpostName`` so the two can
    /// never drift. Used by logs and by the vocabulary-stability test; the
    /// values are a stable contract, not free to rename.
    public var label: String {
      signpostName.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
    }
  }

  /// The process-wide signposter. `category: "phase"` groups every Lorvex phase
  /// interval under one Instruments lane.
  public static let signposter = OSSignposter(subsystem: "com.lorvex.apple", category: "phase")

  /// An in-flight interval. Opaque token pairing the phase with its signpost
  /// state so a caller cannot close an interval under the wrong name. A fresh
  /// per-interval ``OSSignpostID`` keeps overlapping same-phase intervals (two
  /// concurrent DB reads, say) distinct in Instruments.
  public struct Interval {
    let phase: Phase
    let state: OSSignpostIntervalState
  }

  /// Open an interval for `phase`. Must be balanced by ``end(_:)`` on every exit.
  public static func begin(_ phase: Phase) -> Interval {
    let state = signposter.beginInterval(phase.signpostName, id: signposter.makeSignpostID())
    return Interval(phase: phase, state: state)
  }

  /// Close a previously-opened interval.
  public static func end(_ interval: Interval) {
    signposter.endInterval(interval.phase.signpostName, interval.state)
  }

  /// Run `body` bracketed by an interval that ends on return or throw.
  @discardableResult
  public static func withInterval<T>(_ phase: Phase, _ body: () throws -> T) rethrows -> T {
    let interval = begin(phase)
    defer { end(interval) }
    return try body()
  }

  /// Run an async `body` bracketed by an interval that ends on return, throw, or
  /// cancellation.
  @discardableResult
  public static func withInterval<T>(
    _ phase: Phase, _ body: () async throws -> T
  ) async rethrows -> T {
    let interval = begin(phase)
    defer { end(interval) }
    return try await body()
  }
}
