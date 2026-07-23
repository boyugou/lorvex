import Foundation

/// The complete database-backed input to one widget/watch projection, captured
/// from a single SQLite transaction.
///
/// `storageGeneration` is the durable physical-store generation for the managed
/// store. A snapshot writer compares it before workspace identity or local
/// sequence, preventing a delayed pre-reset or pre-quarantine projection from
/// resurrecting superseded titles after a fresh workspace has been published.
/// `logicalDay` is the exact day key used by every date-sensitive query in the
/// transaction. Projectors must not recompute it later from wall time: a source
/// read that straddles midnight still represents the day it was asked to load.
public struct WidgetSnapshotSource: Sendable, Equatable {
  public let storageGeneration: Int
  public let logicalDay: String
  /// IANA timezone that owns ``logicalDay`` and every bounded day query in this
  /// transaction. Projectors and readers must use it for freshness/midnight.
  public let timezone: String
  public let today: TodaySnapshot
  public let currentFocus: CurrentFocusPlan?
  public let habits: HabitCatalogSnapshot?
  public let lists: ListCatalogSnapshot?
  public let stats: WidgetStatsSource?

  public init(
    storageGeneration: Int,
    logicalDay: String,
    timezone: String,
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habits: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?,
    stats: WidgetStatsSource?
  ) {
    self.storageGeneration = max(0, storageGeneration)
    self.logicalDay = logicalDay
    self.timezone = timezone
    self.today = today
    self.currentFocus = currentFocus
    self.habits = habits
    self.lists = lists
    self.stats = stats
  }
}

/// Atomic source read used by every production widget/watch publisher.
///
/// This is a refinement rather than another requirement on the large app core
/// facade: production's `SwiftLorvexCoreService` is the sole implementation,
/// while narrow test doubles can remain intentionally lightweight. Publishers
/// fail if a shipping core lacks this contract instead of silently rebuilding a
/// mixed-revision snapshot through several independent reads.
public protocol LorvexWidgetSnapshotSourceServicing: Sendable {
  /// `date == nil` is the production path: the core captures the configured
  /// product day from SQLite inside the same transaction as every dependent
  /// query. A concrete day is a deterministic test/backfill seam only.
  func loadWidgetSnapshotSource(date: String?) async throws -> WidgetSnapshotSource
}
