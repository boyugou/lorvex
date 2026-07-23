import Foundation
import GRDB
import LorvexDomain

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A row from `task_provider_event_links`. Device-local table (never synced).
public struct TaskProviderEventLink: Sendable, Equatable {
  public let taskId: String
  public let providerKind: String
  public let providerScope: String
  public let providerEventKey: String
  public let createdAt: SyncTimestamp
  public let updatedAt: SyncTimestamp

  public init(
    taskId: String, providerKind: String, providerScope: String, providerEventKey: String,
    createdAt: SyncTimestamp, updatedAt: SyncTimestamp
  ) {
    self.taskId = taskId
    self.providerKind = providerKind
    self.providerScope = providerScope
    self.providerEventKey = providerEventKey
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ProviderEventLinkDeleteResult: Sendable, Equatable {
  public let deleted: Bool
  public let before: TaskProviderEventLink?
  public let remainingLinks: [TaskProviderEventLink]

  public init(
    deleted: Bool, before: TaskProviderEventLink?, remainingLinks: [TaskProviderEventLink]
  ) {
    self.deleted = deleted
    self.before = before
    self.remainingLinks = remainingLinks
  }
}

/// Runtime resolution states for a provider link.
public enum ProviderResolutionState: String, Sendable, Equatable {
  case resolved
  case pending
  case stale
  case unavailable
  case missing
}

/// A provider link joined against the `provider_calendar_events` cache, with a
/// runtime-computed ``ProviderResolutionState``.
public struct ProviderEventLinkWithResolution: Sendable, Equatable {
  public let taskId: String
  public let providerKind: String
  public let providerScope: String
  public let providerEventKey: String
  public let createdAt: SyncTimestamp
  public let updatedAt: SyncTimestamp
  public let eventTitle: String?
  public let eventStartDate: IsoDate.YMD?
  public let eventStartTime: TimeOfDay?
  public let resolutionState: ProviderResolutionState

  public init(
    taskId: String, providerKind: String, providerScope: String, providerEventKey: String,
    createdAt: SyncTimestamp, updatedAt: SyncTimestamp, eventTitle: String?,
    eventStartDate: IsoDate.YMD?, eventStartTime: TimeOfDay?,
    resolutionState: ProviderResolutionState
  ) {
    self.taskId = taskId
    self.providerKind = providerKind
    self.providerScope = providerScope
    self.providerEventKey = providerEventKey
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.eventTitle = eventTitle
    self.eventStartDate = eventStartDate
    self.eventStartTime = eventStartTime
    self.resolutionState = resolutionState
  }
}

/// Inputs to ``ProviderRepo/upsertProviderEvent``.
public struct ProviderEventData: Sendable {
  public let providerKind: String
  public let providerScope: String
  public let providerEventKey: String
  public let title: String?
  public let description: String?
  public let startDate: String
  public let startTime: String?
  public let endDate: String?
  public let endTime: String?
  public let allDay: Bool
  public let location: String?
  public let organizerEmail: String?
  public let sourceTimeKind: String
  public let sourceTzid: String?
  public let recurrence: String?
  public let recurrenceExceptions: String?
  public let color: String?
  public let attendeesJson: String?
  public let videoCallUrl: String?

  public init(
    providerKind: String, providerScope: String, providerEventKey: String,
    title: String? = nil, description: String? = nil,
    startDate: String, startTime: String? = nil,
    endDate: String? = nil, endTime: String? = nil,
    allDay: Bool = false, location: String? = nil, organizerEmail: String? = nil,
    sourceTimeKind: String = "floating", sourceTzid: String? = nil,
    recurrence: String? = nil, recurrenceExceptions: String? = nil,
    color: String? = nil, attendeesJson: String? = nil, videoCallUrl: String? = nil
  ) {
    self.providerKind = providerKind
    self.providerScope = providerScope
    self.providerEventKey = providerEventKey
    self.title = title
    self.description = description
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.organizerEmail = organizerEmail
    self.sourceTimeKind = sourceTimeKind
    self.sourceTzid = sourceTzid
    self.recurrence = recurrence
    self.recurrenceExceptions = recurrenceExceptions
    self.color = color
    self.attendeesJson = attendeesJson
    self.videoCallUrl = videoCallUrl
  }
}

public enum ProviderEventUpsertOutcome: Sendable, Equatable {
  case inserted
  case updated
  case unchanged
}

/// State transition for a provider scope runtime record.
public enum ProviderScopeTransition: Sendable {
  case toggle(enabled: Bool)
  case refreshSuccess(now: String)
  case refreshError(now: String, error: String, resultLabel: String)
  case permissionDenied
}

// ---------------------------------------------------------------------------
// Provider repo
// ---------------------------------------------------------------------------

/// Provider mirror repository — shared CRUD and resolution logic for
/// `provider_calendar_events`, `task_provider_event_links`, and
/// `provider_scope_runtime_state`. All three tables are device-local.
public enum ProviderRepo {

  static let linkSelectColumns =
    "task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at"

  static func isProviderErrorLabel(_ label: String?) -> Bool {
    guard let label else { return false }
    return label == AvailabilityState.permissionDenied
      || label == AvailabilityState.authorizationError
      || label == AvailabilityState.fetchError
      || label == AvailabilityState.parseError
  }

  static func linkFromRow(_ row: Row) throws -> TaskProviderEventLink {
    let rawCreated: String = row[4]
    let rawUpdated: String = row[5]
    guard let createdAt = SyncTimestamp.parse(rawCreated) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message:
          "task_provider_event_links.created_at is not a canonical sync timestamp: \(rawCreated)")
    }
    guard let updatedAt = SyncTimestamp.parse(rawUpdated) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message:
          "task_provider_event_links.updated_at is not a canonical sync timestamp: \(rawUpdated)")
    }
    return TaskProviderEventLink(
      taskId: row[0],
      providerKind: row[1],
      providerScope: row[2],
      providerEventKey: row[3],
      createdAt: createdAt,
      updatedAt: updatedAt)
  }

  // -- task ↔ provider event links ----------------------------------------

  /// Insert or update a task ↔ provider-event link. Returns the upserted row.
  @discardableResult
  public static func upsertProviderEventLink(
    _ db: Database,
    taskId: TaskId,
    providerKind: String,
    providerScope: String,
    providerEventKey: String
  ) throws -> TaskProviderEventLink {
    let now = SyncTimestamp.now().asString
    try db.execute(
      sql: """
        INSERT INTO task_provider_event_links \
            (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at) \
        VALUES (?, ?, ?, ?, ?, ?) \
        ON CONFLICT(task_id, provider_kind, provider_scope, provider_event_key) DO UPDATE SET \
            updated_at = excluded.updated_at
        """,
      arguments: [
        taskId.rawValue, providerKind, providerScope, providerEventKey, now, now,
      ])
    guard
      let link = try getProviderEventLink(
        db, taskId: taskId, providerKind: providerKind,
        providerScope: providerScope, providerEventKey: providerEventKey)
    else {
      throw DatabaseError(
        resultCode: .SQLITE_INTERNAL,
        message: "upsertProviderEventLink: post-insert SELECT returned no row")
    }
    return link
  }

  /// Read a single task ↔ provider-event link by composite key. Returns
  /// `nil` if no row matches.
  public static func getProviderEventLink(
    _ db: Database,
    taskId: TaskId,
    providerKind: String,
    providerScope: String,
    providerEventKey: String
  ) throws -> TaskProviderEventLink? {
    let row = try Row.fetchOne(
      db,
      sql: """
        SELECT \(linkSelectColumns) FROM task_provider_event_links \
        WHERE task_id = ? AND provider_kind = ? AND provider_scope = ? AND provider_event_key = ?
        """,
      arguments: [
        taskId.rawValue, providerKind, providerScope, providerEventKey,
      ])
    guard let row else { return nil }
    return try linkFromRow(row)
  }

  /// Remove a task ↔ provider-event link. Returns whether a row was deleted,
  /// the pre-delete row when one existed, and the remaining links for the
  /// task (so callers can avoid logging no-op deletes).
  public static func deleteProviderEventLink(
    _ db: Database,
    taskId: TaskId,
    providerKind: String,
    providerScope: String,
    providerEventKey: String
  ) throws -> ProviderEventLinkDeleteResult {
    let before = try getProviderEventLink(
      db, taskId: taskId, providerKind: providerKind,
      providerScope: providerScope, providerEventKey: providerEventKey)
    try db.execute(
      sql: """
        DELETE FROM task_provider_event_links \
        WHERE task_id = ? AND provider_kind = ? AND provider_scope = ? AND provider_event_key = ?
        """,
      arguments: [
        taskId.rawValue, providerKind, providerScope, providerEventKey,
      ])
    let deletedRows = db.changesCount

    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT \(linkSelectColumns) FROM task_provider_event_links WHERE task_id = ? \
        ORDER BY created_at, provider_kind, provider_scope, provider_event_key
        """,
      arguments: [taskId.rawValue])
    let remaining = try rows.map(linkFromRow)
    return ProviderEventLinkDeleteResult(
      deleted: deletedRows > 0, before: before, remainingLinks: remaining)
  }

  /// Resolve provider links for a task with computed runtime state. See
  /// ``ProviderResolutionState`` for the five terminal states; the JOIN
  /// against `provider_calendar_events` and `provider_scope_runtime_state` is
  /// single-roundtrip.
  public static func getResolvedProviderLinksForTask(
    _ db: Database, taskId: TaskId
  ) throws -> [ProviderEventLinkWithResolution] {
    let sql = """
      SELECT tpl.task_id, tpl.provider_kind, tpl.provider_scope, tpl.provider_event_key, \
             tpl.created_at, tpl.updated_at, \
             pce.title, pce.start_date, pce.start_time, \
             pce.provider_event_key IS NOT NULL AS has_event, \
             psr.availability_state, \
             psr.last_refresh_success_at, \
             psr.last_refresh_result, \
             psr.provider_kind IS NOT NULL AS has_runtime_state, \
             psr.last_refresh_success_at IS NOT NULL \
               AND psr.last_refresh_success_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours') \
               AS scope_stale \
      FROM task_provider_event_links tpl \
      LEFT JOIN provider_calendar_events pce \
        ON tpl.provider_kind = pce.provider_kind \
       AND tpl.provider_scope = pce.provider_scope \
       AND tpl.provider_event_key = pce.provider_event_key \
      LEFT JOIN provider_scope_runtime_state psr \
        ON tpl.provider_kind = psr.provider_kind \
       AND tpl.provider_scope = psr.provider_scope \
      WHERE tpl.task_id = ? \
      ORDER BY tpl.created_at, tpl.provider_kind, tpl.provider_scope, tpl.provider_event_key
      """
    let rows = try Row.fetchAll(db, sql: sql, arguments: [taskId.rawValue])
    return try rows.map { row in
      let providerKind: String = row[1]
      let rawCreated: String = row[4]
      let rawUpdated: String = row[5]
      guard let createdAt = SyncTimestamp.parse(rawCreated) else {
        throw DatabaseError(
          resultCode: .SQLITE_MISMATCH,
          message:
            "task_provider_event_links.created_at is not a canonical sync timestamp: \(rawCreated)")
      }
      guard let updatedAt = SyncTimestamp.parse(rawUpdated) else {
        throw DatabaseError(
          resultCode: .SQLITE_MISMATCH,
          message:
            "task_provider_event_links.updated_at is not a canonical sync timestamp: \(rawUpdated)")
      }
      let hasEvent: Bool = row[9]
      let availabilityState: String? = row[10]
      let lastRefreshSuccessAt: String? = row[11]
      let lastRefreshResult: String? = row[12]
      let hasRuntimeState: Bool = row[13]
      let scopeStale: Bool = row[14]

      let scopeConfiguredEnabled = hasRuntimeState
      let scopeAvailable = availabilityState == AvailabilityState.enabled
      let scopeFailing =
        isProviderErrorLabel(availabilityState) || isProviderErrorLabel(lastRefreshResult)

      let state: ProviderResolutionState
      if hasEvent {
        state = .resolved
      } else if !scopeConfiguredEnabled {
        state = .unavailable
      } else if !hasRuntimeState {
        state = .pending
      } else if !scopeAvailable || scopeFailing {
        state = .unavailable
      } else if lastRefreshSuccessAt == nil {
        state = .pending
      } else if scopeStale {
        state = .stale
      } else {
        state = .missing
      }

      // Typed start_date / start_time. Non-canonical values surface as
      // SQLITE_MISMATCH so callers don't silently consume garbage.
      let rawStartDate: String? = row[7]
      let rawStartTime: String? = row[8]
      let eventStartDate: IsoDate.YMD?
      if let rawStartDate {
        switch IsoDate.parseIsoDate(rawStartDate) {
        case .success(let ymd):
          eventStartDate = ymd
        case .failure:
          throw DatabaseError(
            resultCode: .SQLITE_MISMATCH,
            message:
              "provider_calendar_events.start_date is not a canonical ISO date: \(rawStartDate)")
        }
      } else {
        eventStartDate = nil
      }
      let eventStartTime: TimeOfDay?
      if let rawStartTime {
        switch TimeOfDay.parse(rawStartTime) {
        case .success(let t):
          eventStartTime = t
        case .failure:
          throw DatabaseError(
            resultCode: .SQLITE_MISMATCH,
            message:
              "provider_calendar_events.start_time is not a canonical HH:MM: \(rawStartTime)")
        }
      } else {
        eventStartTime = nil
      }

      return ProviderEventLinkWithResolution(
        taskId: row[0],
        providerKind: providerKind,
        providerScope: row[2],
        providerEventKey: row[3],
        createdAt: createdAt,
        updatedAt: updatedAt,
        eventTitle: row[6],
        eventStartDate: eventStartDate,
        eventStartTime: eventStartTime,
        resolutionState: state)
    }
  }

  // -- provider_calendar_events --------------------------------------------

  /// Upsert a provider calendar event into the local cache. Distinguishes
  /// fresh inserts, user-visible updates, and same-content no-ops (which
  /// still bump the observation timestamp under a monotonic gate so a
  /// stale concurrent refresh can't clobber a winner).
  public static func upsertProviderEvent(
    _ db: Database, event: ProviderEventData, now: String
  ) throws -> ProviderEventUpsertOutcome {
    let allDayInt: Int64 = event.allDay ? 1 : 0

    // INSERT ... ON CONFLICT DO NOTHING — single-statement insert path.
    try db.execute(
      sql: """
        INSERT INTO provider_calendar_events \
            (provider_kind, provider_scope, provider_event_key, \
             title, description, start_date, start_time, \
             end_date, end_time, all_day, location, organizer_email, \
             source_time_kind, source_tzid, recurrence, recurrence_exceptions, \
             color, attendees_json, video_call_url, \
             last_seen_at) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
        ON CONFLICT(provider_kind, provider_scope, provider_event_key) DO NOTHING
        """,
      arguments: [
        event.providerKind, event.providerScope, event.providerEventKey,
        event.title, event.description, event.startDate, event.startTime,
        event.endDate, event.endTime, allDayInt, event.location, event.organizerEmail,
        event.sourceTimeKind, event.sourceTzid, event.recurrence, event.recurrenceExceptions,
        event.color, event.attendeesJson, event.videoCallUrl,
        now,
      ])
    if db.changesCount == 1 {
      return .inserted
    }

    // Conflict path — gated UPDATE that fires only on visible-content change.
    // Monotonic gate `?now >= last_seen_at` rejects a stale concurrent refresh.
    try db.execute(
      sql: """
        UPDATE provider_calendar_events SET \
           title = ?4, description = ?5, \
           start_date = ?6, start_time = ?7, \
           end_date = ?8, end_time = ?9, \
           all_day = ?10, location = ?11, \
           organizer_email = ?12, \
           source_time_kind = ?13, source_tzid = ?14, \
           recurrence = ?15, recurrence_exceptions = ?16, \
           color = ?17, attendees_json = ?18, \
           video_call_url = ?19, \
           last_seen_at = ?20 \
        WHERE provider_kind = ?1 AND provider_scope = ?2 AND provider_event_key = ?3 \
          AND ?20 >= last_seen_at \
          AND NOT ( \
            title IS ?4 AND description IS ?5 \
            AND start_date IS ?6 AND start_time IS ?7 \
            AND end_date IS ?8 AND end_time IS ?9 \
            AND all_day IS ?10 AND location IS ?11 \
            AND organizer_email IS ?12 \
            AND source_time_kind IS ?13 AND source_tzid IS ?14 \
            AND recurrence IS ?15 AND recurrence_exceptions IS ?16 \
            AND color IS ?17 AND attendees_json IS ?18 \
            AND video_call_url IS ?19 \
          )
        """,
      arguments: [
        event.providerKind, event.providerScope, event.providerEventKey,
        event.title, event.description, event.startDate, event.startTime,
        event.endDate, event.endTime, allDayInt, event.location, event.organizerEmail,
        event.sourceTimeKind, event.sourceTzid, event.recurrence, event.recurrenceExceptions,
        event.color, event.attendeesJson, event.videoCallUrl, now,
      ])
    if db.changesCount == 1 {
      return .updated
    }

    // Identical content: refresh the observation timestamp under the same
    // monotonic guard. Rejection (changesCount == 0) means a racing refresh
    // already wrote a strictly-newer `last_seen_at`; the typed outcome stays
    // `.unchanged` either way. Runtime diagnostics for that race are handled at
    // the surface/telemetry layer.
    try db.execute(
      sql: """
        UPDATE provider_calendar_events SET \
            last_seen_at = ? \
        WHERE provider_kind = ? AND provider_scope = ? AND provider_event_key = ? \
          AND ? >= last_seen_at
        """,
      arguments: [
        now, event.providerKind, event.providerScope, event.providerEventKey, now,
      ])
    return .unchanged
  }

  /// Get all cached event keys for a `(provider_kind, provider_scope)` pair,
  /// optionally filtered by `start_date >= min_start_date`. Used by adapters
  /// to compute stale-key sets for cleanup.
  public static func getProviderEventKeys(
    _ db: Database,
    providerKind: String,
    providerScope: String?,
    minStartDate: String?
  ) throws -> [String] {
    switch (providerScope, minStartDate) {
    case let (scope?, date?):
      return try String.fetchAll(
        db,
        sql: """
          SELECT provider_event_key FROM provider_calendar_events \
          WHERE provider_kind = ? AND provider_scope = ? AND start_date >= ?
          """,
        arguments: [providerKind, scope, date])
    case let (scope?, nil):
      return try String.fetchAll(
        db,
        sql: """
          SELECT provider_event_key FROM provider_calendar_events \
          WHERE provider_kind = ? AND provider_scope = ?
          """,
        arguments: [providerKind, scope])
    case let (nil, date?):
      return try String.fetchAll(
        db,
        sql: """
          SELECT provider_event_key FROM provider_calendar_events \
          WHERE provider_kind = ? AND start_date >= ?
          """,
        arguments: [providerKind, date])
    case (nil, nil):
      return try String.fetchAll(
        db,
        sql: """
          SELECT provider_event_key FROM provider_calendar_events \
          WHERE provider_kind = ?
          """,
        arguments: [providerKind])
    }
  }

  /// Delete a single provider event by its composite key. Returns the
  /// affected-row count.
  @discardableResult
  public static func deleteProviderEvent(
    _ db: Database,
    providerKind: String,
    providerScope: String,
    providerEventKey: String
  ) throws -> Int {
    try db.execute(
      sql: """
        DELETE FROM provider_calendar_events \
        WHERE provider_kind = ? AND provider_scope = ? AND provider_event_key = ?
        """,
      arguments: [providerKind, providerScope, providerEventKey])
    return db.changesCount
  }

  /// Delete all cached events for a specific scope.
  @discardableResult
  public static func clearProviderEventsByScope(
    _ db: Database, providerKind: String, providerScope: String
  ) throws -> Int {
    try db.execute(
      sql: """
        DELETE FROM provider_calendar_events \
        WHERE provider_kind = ? AND provider_scope = ?
        """,
      arguments: [providerKind, providerScope])
    return db.changesCount
  }

  // -- provider_scope_runtime_state ----------------------------------------

  /// Apply a state transition to `provider_scope_runtime_state`. This is
  /// the only production writer for the table — every refresh / toggle /
  /// permission path routes here instead of hand-writing SQL.
  public static func updateProviderScopeState(
    _ db: Database,
    providerKind: String,
    providerScope: String,
    transition: ProviderScopeTransition
  ) throws {
    switch transition {
    case .toggle(let enabled):
      let state = enabled ? AvailabilityState.enabled : AvailabilityState.disabled
      try db.execute(
        sql: """
          INSERT INTO provider_scope_runtime_state \
              (provider_kind, provider_scope, availability_state) \
          VALUES (?, ?, ?) \
          ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
              availability_state = excluded.availability_state
          """,
        arguments: [providerKind, providerScope, state])

    case .refreshSuccess(let now):
      try db.execute(
        sql: """
          INSERT INTO provider_scope_runtime_state \
              (provider_kind, provider_scope, availability_state, \
               last_refresh_attempt_at, last_refresh_success_at, last_refresh_result, last_error) \
          VALUES (?, ?, ?, ?, ?, 'success', NULL) \
          ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
              availability_state = excluded.availability_state, \
              last_refresh_attempt_at = excluded.last_refresh_attempt_at, \
              last_refresh_success_at = excluded.last_refresh_success_at, \
              last_refresh_result = 'success', \
              last_error = NULL
          """,
        arguments: [
          providerKind, providerScope, AvailabilityState.enabled, now, now,
        ])

    case let .refreshError(now, error, resultLabel):
      try db.execute(
        sql: """
          INSERT INTO provider_scope_runtime_state \
              (provider_kind, provider_scope, availability_state, \
               last_refresh_attempt_at, last_refresh_result, last_error) \
          VALUES (?, ?, ?, ?, ?, ?) \
          ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
              availability_state = excluded.availability_state, \
              last_refresh_attempt_at = excluded.last_refresh_attempt_at, \
              last_refresh_result = excluded.last_refresh_result, \
              last_error = excluded.last_error
          """,
        arguments: [
          providerKind, providerScope, resultLabel, now, resultLabel, error,
        ])

    case .permissionDenied:
      try db.execute(
        sql: """
          INSERT INTO provider_scope_runtime_state \
              (provider_kind, provider_scope, availability_state, last_refresh_result) \
          VALUES (?, ?, ?, ?) \
          ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
              availability_state = excluded.availability_state, \
              last_refresh_result = excluded.last_refresh_result
          """,
        arguments: [
          providerKind, providerScope, AvailabilityState.permissionDenied,
          AvailabilityState.permissionDenied,
        ])
    }
  }
}
