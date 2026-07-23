import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// EventKit provider-mirror + write-back facade beside `LorvexCoreServicing`
/// (it does not modify the app-facing protocol). The app reaches it by
/// conditionally casting its `any LorvexCoreServicing`; backends without a
/// provider mirror (the preview service) do not conform, and the EventKit
/// coordinator silently no-ops. Mirrors the `EnvelopeSyncServicing` seam.
///
/// All operations target the device-local `provider_calendar_events` /
/// `task_provider_event_links` / `provider_scope_runtime_state` tables for
/// `provider_kind = eventkit`. None route through `sync_outbox` / CloudKit.
public protocol EventKitProviderServicing: AnyObject, Sendable {
  @discardableResult func ingestEventKitEvents(
    _ events: [ProviderEventData], builtAtMode: CalendarAiAccessMode,
    windowStart: String, windowEnd: String
  ) throws -> Int
  func setEventKitScopeEnabled(_ enabled: Bool) throws
  @discardableResult func clearEventKitMirror() throws -> Int
  @discardableResult func linkTaskToEventKitEvent(
    taskID: String, providerEventKey: String
  ) throws -> TaskProviderEventLink
  @discardableResult func unlinkTaskFromEventKitEvent(
    taskID: String, providerEventKey: String
  ) throws -> ProviderEventLinkDeleteResult
  func eventKitLinksForTask(taskID: String) throws -> [ProviderEventLinkWithResolution]
}

/// EventKit provider mirror + write-back surface on the concrete
/// `SwiftLorvexCoreService`.
///
/// EventKit events are a LOCAL per-device mirror: ingest upserts redacted /
/// verbatim rows into `provider_calendar_events` (kind `eventkit`), the scope
/// runtime state is flipped to `enabled` + `success` so the timeline union's
/// `scopeExists` predicate surfaces them, and Lorvex-originated write-back binds
/// a task to its EventKit event via `task_provider_event_links`. None of this
/// routes through `sync_outbox` / `LorvexSync` / CloudKit — all three provider
/// tables are device-local by schema.
///
/// These methods extend the concrete service, not `LorvexCoreServicing`; the
/// app-facing protocol is unchanged. The app's `EventKitAccessing` layer calls
/// them directly off the main actor.
extension SwiftLorvexCoreService: EventKitProviderServicing {
  /// The single device-wide EventKit provider scope. EventKit has no per-source
  /// scope axis in this design (no human classification UI), so all mirrored
  /// system-calendar events share one scope.
  public static let eventKitScope = "device"

  /// Upsert a batch of ingest-mapped EventKit rows for the `[windowStart,
  /// windowEnd]` date window and reconcile **within that window only**: rows
  /// present in `events` are upserted; cached rows whose `start_date` falls in
  /// the window but whose key is absent from `events` are deleted (the system
  /// event was removed / moved out). Rows outside the window are left untouched
  /// so a navigation to one week never wipes another window's mirror that a
  /// different consumer (MCP timeline, export, intents) may read. The scope
  /// runtime state is marked `enabled` + `refreshSuccess` so the timeline union
  /// includes the rows.
  ///
  /// `events` is the already-redacted output of ``EventKitIngest/providerRows``,
  /// built at `builtAtMode` — the caller's tier snapshot from *before* the slow
  /// EventKit fetch. `windowStart` / `windowEnd` are canonical `yyyy-MM-dd`.
  /// Returns the count of upserted rows (0 when the write is aborted). One write
  /// transaction; safe to call off the main actor.
  ///
  /// Closes the ingest TOCTOU: the caller reads the tier and fetches from
  /// EventKit out of transaction, so a privacy downgrade (Settings / App
  /// Intents) can commit — purging the mirror and
  /// disabling the scope — between the row build and this write. The persisted
  /// tier is re-read inside the transaction; when it is now stricter than
  /// `builtAtMode` (lower ``CalendarAiAccessMode/detailRank``) the write is
  /// aborted entirely — no rows are upserted and the scope is NOT re-enabled — so
  /// pre-downgrade full detail never lands at rest and the scope the downgrade
  /// disabled stays disabled. The downgrade's own purge already cleared the
  /// mirror; the next refresh re-ingests at the now-current tier. A malformed
  /// persisted value throws (fail closed).
  @discardableResult
  public func ingestEventKitEvents(
    _ events: [ProviderEventData], builtAtMode: CalendarAiAccessMode,
    windowStart: String, windowEnd: String
  ) throws -> Int {
    let scope = Self.eventKitScope
    let now = SyncTimestamp.now().asString
    return try write { db in
      let persisted = try DeviceStateRepo.readCalendarAiAccessMode(db)
      guard persisted.detailRank >= builtAtMode.detailRank else {
        return 0
      }
      let keepKeys = Set(events.map(\.providerEventKey))
      // Stale candidates: only rows whose start_date is inside the ingested
      // window. `getProviderEventKeys(minStartDate:)` lower-bounds; the explicit
      // upper bound keeps reconciliation window-local.
      let inWindow = try ProviderRepo.getProviderEventKeys(
        db, providerKind: ProviderKind.eventkit, providerScope: scope,
        minStartDate: windowStart)
      let stale = Set(inWindow).subtracting(keepKeys)
      for staleKey in stale {
        // Re-check the upper bound per row: `getProviderEventKeys` has no
        // upper-bound filter, so guard against deleting a row past windowEnd.
        let startDate = try String.fetchOne(
          db,
          sql: """
            SELECT start_date FROM provider_calendar_events \
            WHERE provider_kind = ? AND provider_scope = ? AND provider_event_key = ?
            """,
          arguments: [ProviderKind.eventkit, scope, staleKey])
        guard let startDate, startDate <= windowEnd else { continue }
        try ProviderRepo.deleteProviderEvent(
          db, providerKind: ProviderKind.eventkit, providerScope: scope,
          providerEventKey: staleKey)
      }
      for event in events {
        _ = try ProviderRepo.upsertProviderEvent(db, event: event, now: now)
      }
      try ProviderRepo.updateProviderScopeState(
        db, providerKind: ProviderKind.eventkit, providerScope: scope,
        transition: .refreshSuccess(now: now))
      return events.count
    }
  }

  /// Flip the EventKit scope's availability. Disabling drops the scope out of
  /// the timeline union (the `scopeExists` predicate requires `enabled`)
  /// without deleting the cached rows; re-enabling restores them.
  public func setEventKitScopeEnabled(_ enabled: Bool) throws {
    try write { db in
      try ProviderRepo.updateProviderScopeState(
        db, providerKind: ProviderKind.eventkit, providerScope: Self.eventKitScope,
        transition: .toggle(enabled: enabled))
    }
  }

  /// Drop every cached EventKit row + the scope runtime state. Used when the
  /// user disables the integration or revokes permission.
  @discardableResult
  public func clearEventKitMirror() throws -> Int {
    try write { db in
      let removed = try ProviderRepo.clearProviderEventsByScope(
        db, providerKind: ProviderKind.eventkit, providerScope: Self.eventKitScope)
      try ProviderRepo.updateProviderScopeState(
        db, providerKind: ProviderKind.eventkit, providerScope: Self.eventKitScope,
        transition: .toggle(enabled: false))
      return removed
    }
  }

  /// Bind a Lorvex task to the EventKit event written into the Lorvex calendar.
  /// `providerEventKey` is the EKEvent's stable identity (the same key scheme
  /// ingest uses). Device-local; never enqueued to the outbox.
  @discardableResult
  public func linkTaskToEventKitEvent(
    taskID: String, providerEventKey: String
  ) throws -> TaskProviderEventLink {
    try write { db in
      try preflightCurrentMCPIdempotency(db)
      let link = try ProviderRepo.upsertProviderEventLink(
        db, taskId: TaskId(trusted: taskID), providerKind: ProviderKind.eventkit,
        providerScope: Self.eventKitScope, providerEventKey: providerEventKey)
      return link
    }
  }

  /// Remove a task ↔ EventKit-event link. Returns the pre-delete row + the
  /// remaining links for the task.
  @discardableResult
  public func unlinkTaskFromEventKitEvent(
    taskID: String, providerEventKey: String
  ) throws -> ProviderEventLinkDeleteResult {
    try write { db in
      try preflightCurrentMCPIdempotency(db)
      let result = try ProviderRepo.deleteProviderEventLink(
        db, taskId: TaskId(trusted: taskID), providerKind: ProviderKind.eventkit,
        providerScope: Self.eventKitScope, providerEventKey: providerEventKey)
      return result
    }
  }

  /// The EventKit link rows for a task, with computed resolution state. Used by
  /// write-back to resolve the EKEvent key when updating / deleting.
  public func eventKitLinksForTask(taskID: String) throws -> [ProviderEventLinkWithResolution] {
    try read { db in
      try ProviderRepo.getResolvedProviderLinksForTask(db, taskId: TaskId(trusted: taskID))
        .filter { $0.providerKind == ProviderKind.eventkit }
    }
  }
}
