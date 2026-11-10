import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

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
  /// The keys of the mirrored repeating series.
  func recurringEventKitMirrorKeys() throws -> [String]
  /// Remove the mirrored series `keys` and their moved occurrences.
  @discardableResult func removeEventKitMirrorRows(keys: Set<String>) throws -> Int
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
  /// present in `events` are upserted, and cached rows the window covers whose
  /// key is absent from `events` are deleted (the system event was removed or
  /// moved out). A row is covered when its `start_date` falls in the window,
  /// or when it is a one-off event the mirror shows on a day strictly inside
  /// the window: the rest of a multi-day event that began earlier, which
  /// Calendar returns for any window it overlaps. Rows the window does not
  /// cover are left untouched so a navigation to one week never wipes another
  /// window's mirror that a different consumer (MCP timeline, export, intents)
  /// may read. A repeating series that began before the window is not covered:
  /// one window's fetch does not show that the series is gone. The scope
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
      // One-off events that began before the window and still show inside it.
      let spanning = try Self.eventKitOneOffKeysShownInside(
        db, windowStart: windowStart, windowEnd: windowEnd
      ).subtracting(keepKeys)
      for staleKey in spanning {
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

  /// The keys of the one-off EventKit rows the mirror shows on the days
  /// strictly inside `[windowStart, windowEnd]`.
  ///
  /// The first and last day are left out on purpose. EventKit is asked for the
  /// instants the window spans in the planner's zone, while an all-day event
  /// belongs to a calendar day in its own; on an edge day the two can disagree
  /// about whether an event is in the window, and an event EventKit did not
  /// return for that reason must not be taken for a deleted one. A window too
  /// short to have an inside yields nothing.
  private static func eventKitOneOffKeysShownInside(
    _ db: Database, windowStart: String, windowEnd: String
  ) throws -> Set<String> {
    guard case .success(let first) = IsoDate.parseIsoDate(windowStart),
      case .success(let last) = IsoDate.parseIsoDate(windowEnd)
    else { return [] }
    let from = IsoDate.addingDays(first, 1).canonicalString
    let to = IsoDate.addingDays(last, -1).canonicalString
    guard from <= to else { return [] }
    return try CalendarTimelineQueries.oneOffProviderEventKeysShown(
      db, providerKind: ProviderKind.eventkit, providerScope: eventKitScope,
      from: from, to: to,
      anchorTimezone: try WorkflowTimezone.activeTimezoneName(db) ?? TimeZone.current.identifier)
  }

  /// The keys of the mirrored repeating series: rows with a rule. A window's
  /// ingest never infers that one is gone (see
  /// ``ingestEventKitEvents(_:builtAtMode:windowStart:windowEnd:)``); the app
  /// looks each up in Calendar and passes the missing ones to
  /// ``removeEventKitMirrorRows(keys:)``.
  public func recurringEventKitMirrorKeys() throws -> [String] {
    try read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT provider_event_key FROM provider_calendar_events
          WHERE provider_kind = ? AND provider_scope = ? AND recurrence IS NOT NULL
          ORDER BY provider_event_key
          """,
        arguments: [ProviderKind.eventkit, Self.eventKitScope])
    }
  }

  /// Remove the mirrored series `keys` together with the rows of their moved
  /// occurrences, which are keyed `"{seriesKey}:{originalYmd}"`. Returns the
  /// count of rows removed.
  @discardableResult
  public func removeEventKitMirrorRows(keys: Set<String>) throws -> Int {
    guard !keys.isEmpty else { return 0 }
    let scope = Self.eventKitScope
    return try write { db in
      var removed = 0
      for key in keys.sorted() {
        let prefix = key + ":"
        let rows = try String.fetchAll(
          db,
          sql: """
            SELECT provider_event_key FROM provider_calendar_events
            WHERE provider_kind = ? AND provider_scope = ?
              AND (provider_event_key = ? OR substr(provider_event_key, 1, ?) = ?)
            """,
          arguments: [ProviderKind.eventkit, scope, key, prefix.count, prefix])
        for row in rows {
          try ProviderRepo.deleteProviderEvent(
            db, providerKind: ProviderKind.eventkit, providerScope: scope,
            providerEventKey: row)
          removed += 1
        }
      }
      return removed
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
