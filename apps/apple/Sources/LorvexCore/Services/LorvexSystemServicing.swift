import Foundation

public protocol LorvexSystemServicing: Sendable {
  func loadRuntimeDiagnostics() async throws -> RuntimeDiagnosticsSnapshot

  /// Cloud Sync queue state derived from the local outbox: the pending /
  /// retrying / failed depths, the oldest and newest pending `created_at`, the
  /// newest per-row push error still attached to an unsynced row, this device's
  /// sync id, and the `reseed_required` checkpoint.
  ///
  /// The same value ``loadRuntimeDiagnostics()`` reports as its `sync` member,
  /// read on its own — no Overview snapshot, task/list counts, changelog page,
  /// or merged log stream — so a surface that only needs the queue depth pays
  /// for one narrow read instead of the whole diagnostics composition, and can
  /// therefore keep a displayed depth live. `backend` is a fixed `"unknown"`
  /// placeholder here: the effective transport is app-runtime state (persisted
  /// mode plus CloudKit account) that a database-only read cannot observe, and
  /// `lastSyncedAt` is likewise runtime state the app layer owns.
  func loadSyncStatus() async throws -> SyncStatusSnapshot

  func loadAIChangelog(
    limit: Int?,
    offset: Int?,
    entityType: String?,
    operation: String?,
    entityID: String?,
    since: String?
  ) async throws -> AIChangelogSnapshot

  /// Merged, newest-first diagnostic log stream across `error_logs`,
  /// `ai_changelog`, and `sync_outbox`, with optional source/level/since
  /// filters and offset/limit pagination. When `redact` is true, summaries and
  /// details are passed through `Diagnostics.redactDiagnosticText`.
  func loadRecentLogs(
    limit: Int,
    offset: Int,
    since: String?,
    levels: [String]?,
    sources: [String]?,
    redact: Bool
  ) async throws -> RecentLogsPage

  /// Append one best-effort diagnostic row to the `error_logs` ring, which the
  /// read surfaces (``loadRecentLogs(limit:offset:since:levels:sources:redact:)``
  /// / ``loadRuntimeDiagnostics()``) merge newest-first. For app-level
  /// observability writers — notably the MetricKit crash/hang subscriber — that
  /// are not sync mutations and so bypass the HLC/outbox write surface. `level`
  /// is normalized to one of `debug`/`info`/`warn`/`error`; an empty `source` or
  /// `message` is dropped. The on-disk backend swallows the insert failure so a
  /// broken diagnostics ring never eclipses the event being logged.
  func appendDiagnosticLog(
    source: String, level: String, message: String, details: String?
  ) async throws

  func getAllPreferences() async throws -> PreferencesSnapshot

  func getPreference(key: String) async throws -> String?

  func setPreference(key: String, value: String) async throws -> String

  func deletePreference(key: String) async throws

  func completeSetup(workingHours: String?, defaultListID: String?, timezone: String?)
    async throws -> PreferencesSnapshot

  func getOverviewCompact() async throws -> OverviewCompactSnapshot

  func loadOverviewTaskList() async throws -> OverviewTaskListSnapshot

  func getSessionContext() async throws -> SessionContextSnapshot

  /// Records that the MCP client identified by `clientName` is active on this
  /// device. Device-local bookkeeping for Settings: never synced, exported, or
  /// logged as an assistant change.
  func recordAssistantActivity(clientName: String, clientTitle: String?, clientVersion: String?)
    async throws

  /// The MCP clients that have used this device's helper, most recently active
  /// first.
  func loadAssistantSessions() async throws -> [AssistantSessionRecord]
}
