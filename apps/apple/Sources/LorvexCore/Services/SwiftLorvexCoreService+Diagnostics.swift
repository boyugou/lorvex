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
  /// queue depths (`pendingCount` / `retryingCount` / `failedCount`) and
  /// oldest/newest pending timestamps are computed live from `sync_outbox`,
  /// and the device id + `reseed_required` checkpoint are surfaced. `backend`
  /// is a fixed `"unknown"` placeholder: the effective Cloud Sync transport is
  /// app-runtime state — the persisted `CloudSyncMode`, its
  /// `LORVEX_CLOUDKIT_EXPORT` override, and CloudKit account status — that this
  /// DB-only call (which also runs inside the separate MCP-host process) cannot
  /// observe, so it reports `"unknown"` rather than asserting a specific mode.
  /// The app layer, which knows the mode, derives the user-facing backend label
  /// from it. `recentLogs` is the
  /// merged newest-first stream over `error_logs` + `ai_changelog` +
  /// `sync_outbox` (bounded slice here; the `get_recent_logs` tool exposes the
  /// filtered/paginated form). `guide` is static copy, matching the Preview
  /// service.
  public func loadRuntimeDiagnostics() async throws -> RuntimeDiagnosticsSnapshot {
    try read { db in
      let overview = try Overview.loadOverviewSnapshot(db, limits: Overview.Limits.app())
      let preferences = try Self.readPreferences(db)
      let taskCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE archived_at IS NULL") ?? 0
      let listCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists") ?? 0
      let deviceID = try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId)
      let reseedRequired =
        try SyncCheckpoints.get(db, key: SyncCheckpoints.keyReseedRequired) == "true"

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
            mcpTool: row.mcpTool
          )
        },
        truncated: changelogRows.count >= 8,
        nextOffset: nil
      )

      // Real outbox-derived queue depths. The "ready" predicate matches
      // `Outbox.getPending` (unsynced and under the retry cap), so
      // `pendingCount` agrees with `list_pending_outbox_entries`. `retryingCount`
      // is the ready subset that has already failed at least once; `failedCount`
      // is the ordinary retry-wait tail. Intentional authoritative-adoption
      // fences are not reported as push failures.
      let readyPredicate =
        "synced_at IS NULL AND disposition IS NULL "
        + "AND retry_count < \(Outbox.maxRetries)"
      let pendingCount =
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE \(readyPredicate)") ?? 0
      let retryingCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL "
          + "AND disposition IS NULL "
          + "AND retry_count > 0 AND retry_count < \(Outbox.maxRetries)") ?? 0
      let failedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL "
          + "AND disposition = ?",
        arguments: [Outbox.Disposition.retryWait.rawValue]) ?? 0
      let oldestPendingAt = try String.fetchOne(
        db, sql: "SELECT MIN(created_at) FROM sync_outbox WHERE \(readyPredicate)")
      let newestPendingAt = try String.fetchOne(
        db, sql: "SELECT MAX(created_at) FROM sync_outbox WHERE \(readyPredicate)")

      let sync = SyncStatusSnapshot(
        backend: "unknown",
        pendingCount: pendingCount,
        retryingCount: retryingCount,
        failedCount: failedCount,
        oldestPendingAt: oldestPendingAt,
        newestPendingAt: newestPendingAt,
        lastSyncedAt: nil,
        lastError: nil,
        deviceID: deviceID,
        reseedRequired: reseedRequired
      )

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

      let guide = GuideSnapshot(
        topic: "overview",
        summary: "Lorvex is running on the pure-Swift core (\(overview.stats.openCount) open task\(overview.stats.openCount == 1 ? "" : "s")).",
        suggestedActions: [
          "Use the MCP host as the primary write surface.",
          "Open the diagnostics panel before packaging or syncing changes.",
        ]
      )

      return RuntimeDiagnosticsSnapshot(
        setup: setup, sync: sync, changelog: changelog, recentLogs: recentLogs, guide: guide)
    }
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
    let clampedOffset = max(offset ?? 0, 0)
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
          mcpTool: row.mcpTool)
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
    let clampedOffset = max(offset, 0)
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
          level: disposition == Outbox.Disposition.authoritativeAdoption.rawValue
            ? .info : (retry > 0 ? .warn : .info),
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
  /// Focus plan/schedule clears are recorded as `delete` operations but are
  /// routine planning actions, not destructive data loss, so they stay at
  /// `info` regardless of operation — only genuine entity deletes
  /// (task/list/habit/calendar_event/memory) and feedback warn.
  static func recentLogChangelogLevel(operation: String, entityType: EntityKind) -> DiagnosticLogLevel {
    switch entityType {
    case .currentFocus, .focusSchedule: return .info
    default: break
    }
    switch operation {
    case "feedback", "delete", "cancel", "permanent_delete": return .warn
    default: return .info
    }
  }
}
