import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Runtime diagnostics

  /// Composes the diagnostics surface from the live core store.
  ///
  /// Real today: `setup` (task/list counts + preference-derived working hours
  /// and default list), `changelog` (AI changelog rows), and `sync` — its
  /// queue depths (`pendingCount` / `retryingCount` / `failedCount`),
  /// oldest/newest pending timestamps, and newest unsynced-row push error are
  /// computed live from `sync_outbox`,
  /// and the device id + `reseed_required` checkpoint are surfaced. `backend`
  /// is a fixed `"unknown"` placeholder: the effective Cloud Sync transport is
  /// app-runtime state — the persisted `CloudSyncMode`, its
  /// `LORVEX_CLOUD_SYNC` override, and CloudKit account status — that this
  /// DB-only call (which also runs inside the separate MCP-host process) cannot
  /// observe, so it reports `"unknown"` rather than asserting a specific mode.
  /// The app layer, which knows the mode, derives the user-facing backend label
  /// from it; ``loadSyncStatus()`` returns that same `sync` member on its own.
  /// `recentLogs` is the
  /// merged newest-first stream over `error_logs` + `ai_changelog` +
  /// `sync_outbox` (bounded slice here; the `get_recent_logs` tool exposes the
  /// filtered/paginated form).
  public func loadRuntimeDiagnostics() async throws -> RuntimeDiagnosticsSnapshot {
    try read { db in
      let preferences = try Self.readPreferences(db)
      let taskCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE archived_at IS NULL") ?? 0
      let listCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists") ?? 0

      let setup = SetupStatusSnapshot(
        setupCompleted: Self.preferenceBool(preferences["setup_completed"]) ?? false,
        setupState: Self.preferenceString(preferences["setup_state"]) ?? "ready",
        listCount: listCount,
        taskCount: taskCount,
        defaultListID: Self.preferenceString(preferences["default_list_id"]),
        workingHours: Self.workingHoursLabel(preferences["working_hours"])
      )

      let changelogRows = try AiChangelogQueryRepo.listAiChangelog(
        db, query: AiChangelogQuery(limit: 8))
      let changelog = AIChangelogSnapshot(
        entries: changelogRows.map { row in
          AIChangelogEntry(
            id: row.id,
            timestamp: row.timestamp,
            entityType: row.entityType.rawValue,
            operation: row.operation,
            entityId: row.entityId,
            summary: row.summary,
            initiatedBy: row.initiatedBy,
            mcpTool: row.mcpTool,
            hasBefore: row.hasBefore,
            hasAfter: row.hasAfter,
            entityTitle: row.entityTitle
          )
        },
        truncated: changelogRows.count >= 8,
        nextOffset: nil
      )

      let sync = try Self.readSyncStatus(db)

      // The diagnostics panel shows a bounded, unfiltered, newest-first slice
      // of the merged log stream; the MCP `get_recent_logs` tool uses the same
      // merge with caller-supplied filters/pagination via `loadRecentLogs`.
      let recentPage = try Self.mergedRecentLogs(
        db, limit: 20, offset: 0, since: nil, levels: nil, sources: nil, redact: true)
      let recentLogs = RecentLogsSnapshot(
        entries: recentPage.entries,
        redactionApplied: recentPage.redactionApplied,
        sourceCounts: recentPage.sourceCounts
      )

      return RuntimeDiagnosticsSnapshot(
        setup: setup, sync: sync, changelog: changelog, recentLogs: recentLogs)
    }
  }

  /// Reads the Cloud Sync queue state on its own, without the rest of the
  /// diagnostics surface.
  ///
  /// Touches only `sync_outbox` and the two sync checkpoints — no Overview
  /// snapshot, preferences, task/list counts, changelog page, or merged log
  /// stream — so a status surface can re-read it whenever it repaints. The
  /// result is field-for-field the `sync` member ``loadRuntimeDiagnostics()``
  /// reports (both build it through ``readSyncStatus(_:)``), including the fixed
  /// `"unknown"` `backend` placeholder, which stands for a transport this
  /// DB-only call cannot observe.
  public func loadSyncStatus() async throws -> SyncStatusSnapshot {
    try read { db in try Self.readSyncStatus(db) }
  }

  /// The `sync_outbox` "ready to push" predicate: unsynced, no terminal
  /// disposition, still under the retry cap. Matches `Outbox.getPending`, so
  /// every depth and timestamp derived from it describes exactly the rows the
  /// next cycle would drain (and agrees with `list_pending_outbox_entries`).
  static let outboxReadyPredicate =
    "synced_at IS NULL AND disposition IS NULL AND retry_count < \(Outbox.maxRetries)"

  /// Builds the outbox-derived sync status inside an open read.
  ///
  /// The single definition behind both ``loadSyncStatus()`` and the `sync`
  /// member of ``loadRuntimeDiagnostics()``, so a narrow status refresh and a
  /// full diagnostics load can never report different queue depths.
  ///
  /// `pendingCount` counts the ready rows (``outboxReadyPredicate``);
  /// `retryingCount` is the ready subset that has already failed at least once;
  /// `failedCount` is the ordinary retry-wait tail. Future-record holds carry
  /// their own disposition and so are not reported as push failures.
  ///
  /// `lastError` is the newest `sync_outbox.last_error` still attached to an
  /// unsynced row — the transport's own words for why that row did not upload,
  /// which the push path persists per row precisely so one failure cannot
  /// overwrite another's. Quarantined rows are included: a row the retry ladder
  /// gave up on is the most diagnostic thing the queue holds. It is nil only
  /// when no unsynced row has ever failed, which distinguishes a queue that is
  /// merely waiting for a cycle from one that is failing.
  ///
  /// `backend` is a fixed `"unknown"` placeholder: the effective Cloud Sync
  /// transport is app-runtime state — the persisted `CloudSyncMode`, its
  /// `LORVEX_CLOUD_SYNC` override, and the CloudKit account status — that a
  /// database read (which also runs inside the separate MCP-host process) cannot
  /// observe. `lastSyncedAt` is likewise runtime state the app layer owns, so it
  /// is nil here.
  static func readSyncStatus(_ db: Database) throws -> SyncStatusSnapshot {
    let pendingCount =
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE \(outboxReadyPredicate)")
      ?? 0
    let retryingCount = try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM sync_outbox WHERE \(outboxReadyPredicate) "
        + "AND retry_count > 0") ?? 0
    let failedCount = try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL "
        + "AND disposition = ?",
      arguments: [Outbox.Disposition.retryWait.rawValue]) ?? 0
    let oldestPendingAt = try String.fetchOne(
      db, sql: "SELECT MIN(created_at) FROM sync_outbox WHERE \(outboxReadyPredicate)")
    let newestPendingAt = try String.fetchOne(
      db, sql: "SELECT MAX(created_at) FROM sync_outbox WHERE \(outboxReadyPredicate)")
    // SQLite orders NULL below every value, so a `DESC` sort puts a row that
    // carries an error but no retry stamp last rather than first.
    let lastError = try String.fetchOne(
      db,
      sql: "SELECT last_error FROM sync_outbox "
        + "WHERE synced_at IS NULL AND last_error IS NOT NULL AND last_error <> '' "
        + "ORDER BY last_retry_at DESC, id DESC LIMIT 1")

    return SyncStatusSnapshot(
      backend: "unknown",
      pendingCount: pendingCount,
      retryingCount: retryingCount,
      failedCount: failedCount,
      oldestPendingAt: oldestPendingAt,
      newestPendingAt: newestPendingAt,
      lastSyncedAt: nil,
      lastError: lastError,
      deviceID: try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId),
      reseedRequired: try SyncCheckpoints.get(db, key: SyncCheckpoints.keyReseedRequired) == "true"
    )
  }

  public func loadAIChangelog(
    limit: Int?,
    offset: Int?,
    entityType: String?,
    operation: String?,
    entityID: String?,
    since: String?
  ) async throws -> AIChangelogSnapshot {
    let clampedLimit = min(max(limit ?? 50, 1), 500)
    let clampedOffset = LorvexPageBounds.clampedOffset(offset ?? 0)
    return try read { db in
      let parsedEntityType = entityType.flatMap(EntityKind.parse)
      if entityType != nil, parsedEntityType == nil {
        return AIChangelogSnapshot(entries: [], truncated: false, nextOffset: nil)
      }

      let query = AiChangelogQuery(
        limit: clampedLimit + clampedOffset + 1,
        entityType: parsedEntityType,
        operation: operation,
        entityId: entityID,
        since: since)
      let rows = try AiChangelogQueryRepo.listAiChangelog(db, query: query)
      let pageRows = Array(rows.dropFirst(clampedOffset).prefix(clampedLimit))
      let entries = pageRows.map { row in
        AIChangelogEntry(
          id: row.id,
          timestamp: row.timestamp,
          entityType: row.entityType.rawValue,
          operation: row.operation,
          entityId: row.entityId,
          summary: row.summary,
          initiatedBy: row.initiatedBy,
          mcpTool: row.mcpTool,
          hasBefore: row.hasBefore,
          hasAfter: row.hasAfter,
          entityTitle: row.entityTitle)
      }
      let truncated = rows.count > clampedOffset + clampedLimit
      return AIChangelogSnapshot(
        entries: entries,
        truncated: truncated,
        nextOffset: truncated ? clampedOffset + pageRows.count : nil)
    }
  }

  public func loadRecentLogs(
    limit: Int,
    offset: Int,
    since: String?,
    levels: [String]?,
    sources: [String]?,
    redact: Bool
  ) async throws -> RecentLogsPage {
    let clampedLimit = min(max(limit, 1), 500)
    let clampedOffset = LorvexPageBounds.clampedOffset(offset)
    return try read { db in
      try Self.mergedRecentLogs(
        db, limit: clampedLimit, offset: clampedOffset, since: since,
        levels: levels, sources: sources, redact: redact)
    }
  }

  /// Route an observability diagnostic to the `error_logs` ring. Redaction,
  /// UTF-8 byte-budget truncation, and empty-value dropping happen inside
  /// ``LorvexStore/ErrorLog/appendBestEffort(_:source:message:details:level:)``;
  /// the insert itself is best-effort (never throws) so a full or broken ring
  /// cannot eclipse the diagnostic. The surrounding `write` can still throw if
  /// the store fails to open.
  public func appendDiagnosticLog(
    source: String, level: String, message: String, details: String?
  ) async throws {
    try write { db in
      ErrorLog.appendBestEffort(
        db, source: source, message: message, details: details, level: level)
    }
  }

  /// Per-source scan cap before merge: bounds how many rows each source
  /// contributes so a large backlog cannot materialize an unbounded batch.
  static let recentLogScanCap = 500

  /// Merge `error_logs` + `ai_changelog` + `sync_outbox` into one newest-first
  /// stream, apply source/level/since filters, then offset+limit. Each row
  /// carries a per-source id prefix, level, summary, and details. `redact` runs
  /// the surviving page's summaries/details through
  /// ``Diagnostics/redactDiagnosticText(_:)``.
  static func mergedRecentLogs(
    _ db: Database,
    limit: Int,
    offset: Int,
    since: String?,
    levels: [String]?,
    sources: [String]?,
    redact: Bool
  ) throws -> RecentLogsPage {
    func wants(_ source: String) -> Bool { sources?.contains(source) ?? true }

    var merged: [RecentLogEntry] = []

    if wants("error_log") {
      var sql = "SELECT id, source, level, message, details, created_at FROM error_logs"
      var args: [DatabaseValueConvertible] = []
      if let since { sql += " WHERE created_at > ?"; args.append(since) }
      // rowid tie-break: same-millisecond appends share `created_at`, and the
      // UUIDv7 ids' random tails give an arbitrary same-ms order — rowid is
      // the actual insertion order, keeping newest-first deterministic.
      sql += " ORDER BY created_at DESC, rowid DESC LIMIT ?"
      args.append(recentLogScanCap)
      for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)) {
        let id: String = row["id"]
        let levelRaw: String = row["level"]
        merged.append(RecentLogEntry(
          id: "error:\(id)", timestamp: row["created_at"], source: "error_log",
          level: DiagnosticLogLevel(lenient: levelRaw) ?? .info, summary: row["message"],
          details: row["details"], origin: row["source"]))
      }
    }

    if wants("ai_changelog") {
      let rows = try AiChangelogQueryRepo.listAiChangelog(
        db, query: AiChangelogQuery(limit: recentLogScanCap, since: since))
      for row in rows {
        merged.append(RecentLogEntry(
          id: "changelog:\(row.id)", timestamp: row.timestamp, source: "ai_changelog",
          level: recentLogChangelogLevel(operation: row.operation, entityType: row.entityType),
          summary: row.summary,
          details: row.mcpTool.map { "tool=\($0)" }))
      }
    }

    if wants("sync_outbox") {
      var sql = "SELECT id, entity_type, entity_id, operation, created_at, synced_at, retry_count, "
        + "consecutive_error_count, disposition, next_retry_at, recovery_round "
        + "FROM sync_outbox"
      var args: [DatabaseValueConvertible] = []
      if let since { sql += " WHERE created_at > ?"; args.append(since) }
      sql += " ORDER BY created_at DESC LIMIT ?"
      args.append(recentLogScanCap)
      for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)) {
        let id: Int64 = row["id"]
        let retry: Int64 = row["retry_count"]
        let syncedAt: String? = row["synced_at"]
        let entityType: String = row["entity_type"]
        let entityId: String = row["entity_id"]
        let operation: String = row["operation"]
        let consecutiveErrorCount: Int64 = row["consecutive_error_count"]
        let disposition: String? = row["disposition"]
        let nextRetryAt: String? = row["next_retry_at"]
        let recoveryRound: Int64 = row["recovery_round"]
        let details: String? =
          syncedAt.map { "synced_at=\($0)" }
          ?? disposition.map {
            var value =
              "disposition=\($0), retry_count=\(retry), "
              + "consecutive_error_count=\(consecutiveErrorCount)"
            if let nextRetryAt {
              value += ", next_retry_at=\(nextRetryAt), recovery_round=\(recoveryRound)"
            }
            return value
          }
          ?? (retry > 0
            ? "retry_count=\(retry), consecutive_error_count=\(consecutiveErrorCount)" : nil)
        merged.append(RecentLogEntry(
          id: "sync:\(id)", timestamp: row["created_at"], source: "sync_outbox",
          level: retry > 0 ? .warn : .info,
          summary: "\(operation) \(entityType):\(entityId)", details: details))
      }
    }

    let filtered =
      merged
      .filter { levels?.contains($0.level.rawValue) ?? true }
      .sorted { ($0.timestamp ?? "") > ($1.timestamp ?? "") }

    var sourceCounts: [String: Int] = [:]
    for entry in filtered { sourceCounts[entry.source, default: 0] += 1 }

    let page = Array(filtered.dropFirst(offset).prefix(limit)).map { entry -> RecentLogEntry in
      guard redact else { return entry }
      var redacted = entry
      redacted.summary = Diagnostics.redactDiagnosticText(entry.summary)
      redacted.details = entry.details.map(Diagnostics.redactDiagnosticText)
      return redacted
    }

    return RecentLogsPage(
      entries: page, totalMatching: filtered.count, sourceCounts: sourceCounts,
      redactionApplied: redact)
  }

  /// Map a changelog operation onto a log level: destructive ops and feedback
  /// warn.
  ///
  /// Clearing a day's briefing is recorded as a `delete` operation, but it and
  /// saving a day's times are routine planning actions, not destructive data
  /// loss, so they stay at `info` regardless of operation — only genuine
  /// entity deletes (task/list/habit/calendar_event/memory) and feedback warn.
  static func recentLogChangelogLevel(operation: String, entityType: EntityKind) -> DiagnosticLogLevel {
    switch entityType {
    case .dailyBriefing, .dailySchedule: return .info
    default: break
    }
    switch operation {
    case "feedback", "delete", "cancel", "permanent_delete": return .warn
    default: return .info
    }
  }
}
