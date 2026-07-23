import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `LorvexReviewServicing` over the pure-Swift core.
///
/// Daily-review reads/writes go through `DailyReviewOpsRepo`; writes funnel
/// through the `+WriteSurface` adapter (one HLC version per mutation stamping
/// the parent row plus its link materializers). The write date is resolved and
/// staleness-gated via `DailyReviewDate.resolveDailyReviewWriteDate`, and the
/// non-optional repo `timezone` is taken from the active timezone preference.
/// Weekly review composes `WeeklyReview.loadWeeklyReviewSnapshot` with the MCP
/// snapshot limits (5/3/5/5). Mapping reuses `SwiftLorvexReviewDeserializers`.
extension SwiftLorvexCoreService {

  // MARK: - Daily review reads

  public func loadDailyReview(date: String?) async throws -> DailyReviewEntry? {
    try read { db in
      let resolved: String
      if let date, !date.isEmpty {
        resolved = date
      } else {
        resolved = try WorkflowTimezone.todayYmdForConn(db)
      }
      guard let row = try DailyReviewOpsRepo.getDailyReviewRow(db, date: resolved) else {
        return nil
      }
      return SwiftLorvexReviewDeserializers.dailyReview(row)
    }
  }

  public func getReviewHistory(from: String?, to: String?, limit: Int?) async throws
    -> [DailyReviewEntry]
  {
    try read { db in try Self.reviewHistory(db, from: from, to: to, limit: limit) }
  }

  static func reviewHistory(
    _ db: Database, from: String?, to: String?, limit: Int?
  ) throws -> [DailyReviewEntry] {
    let query = DailyReviewHistoryQuery(
      since: from, until: to, limit: max(1, limit ?? 30), offset: 0)
    let page = try DailyReviewOpsRepo.listDailyReviewRows(db, query: query)
    return page.rows.map(SwiftLorvexReviewDeserializers.dailyReview)
  }

  // MARK: - Daily review writes

  public func upsertDailyReview(
    date: String?,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    linkedTaskIDs: [String],
    linkedListIDs: [String]
  ) async throws -> DailyReviewEntry {
    try await writeInteractiveDailyReview(
      date: date, summary: summary, mood: mood, energyLevel: energyLevel,
      wins: wins, blockers: blockers, learnings: learnings,
      linkedTaskIDs: linkedTaskIDs, linkedListIDs: linkedListIDs)
  }

  public func upsertDailyReviewPreservingLinks(
    date: String?,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?
  ) async throws -> DailyReviewEntry {
    try await writeInteractiveDailyReview(
      date: date, summary: summary, mood: mood, energyLevel: energyLevel,
      wins: wins, blockers: blockers, learnings: learnings,
      linkedTaskIDs: nil, linkedListIDs: nil)
  }

  /// Shared interactive write funnel. `nil` link sets mean preserve the sets
  /// present inside this transaction; non-nil sets are a canonical full
  /// replacement. Keeping the tri-state private prevents public callers from
  /// accidentally treating omission as either clear or preserve.
  private func writeInteractiveDailyReview(
    date: String?,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    linkedTaskIDs: [String]?,
    linkedListIDs: [String]?
  ) async throws -> DailyReviewEntry {
    try withWrite { db, hlc, deviceId in
      let resolved = try Self.resolveReviewDate(db, requestedDate: date)
      let timezone =
        try WorkflowTimezone.activeTimezoneName(db) ?? TimeZone.current.identifier
      let params = UpsertDailyReviewParams(
        date: resolved, summary: summary, mood: mood.map(Int64.init),
        energyLevel: energyLevel.map(Int64.init), wins: wins, blockers: blockers,
        learnings: learnings, timezone: timezone,
        version: hlc.nextVersionString(), now: SyncTimestampFormat.syncTimestampNow())
      let applied = try DailyReviewOpsRepo.upsertDailyReview(db, params: params)
      try DailyReviewOpsRepo.requireDailyReviewWriteApplied(applied, date: resolved)
      return try Self.finishDailyReviewWrite(
        db, service: self, hlc: hlc, deviceId: deviceId, date: resolved,
        operation: SyncNaming.opUpsert,
        linkedTaskIds: linkedTaskIDs, linkedListIds: linkedListIDs)
    }
  }

  public func importDailyReview(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    timezone: String? = nil,
    updatedAt: String? = nil,
    linkedTaskIDs: [String]? = nil,
    linkedListIDs: [String]? = nil
  ) async throws -> DailyReviewEntry {
    try withWrite { db, hlc, deviceId in
      try self.writeImportedDailyReviewInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, summary: summary, mood: mood,
        energyLevel: energyLevel, wins: wins, blockers: blockers, learnings: learnings,
        timezone: timezone, updatedAt: updatedAt,
        linkedTaskIDs: linkedTaskIDs, linkedListIDs: linkedListIDs)
    }
  }

  public func importDailyReviewIfAbsent(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    timezone: String?,
    updatedAt: String?,
    linkedTaskIDs: [String]?,
    linkedListIDs: [String]?
  ) async throws -> Bool {
    try withWrite { db, hlc, deviceId in
      // A daily review is a singleton per date. A non-destructive restore skips a
      // date a concurrent write already holds (no overwrite of newer journal
      // content) and one the user deleted after the backup (no resurrection at a
      // fresh dominating import HLC). Both checks share this write lock.
      let resolved = try Self.canonicalReviewDate(date)
      if try Int.fetchOne(
        db, sql: "SELECT 1 FROM daily_reviews WHERE date = ?", arguments: [resolved]) != nil
      {
        return false
      }
      if try Tombstone.isTombstoned(db, entityType: EntityName.dailyReview, entityId: resolved) {
        return false
      }
      _ = try self.writeImportedDailyReviewInTx(
        db, hlc: hlc, deviceId: deviceId, date: date, summary: summary, mood: mood,
        energyLevel: energyLevel, wins: wins, blockers: blockers, learnings: learnings,
        timezone: timezone, updatedAt: updatedAt,
        linkedTaskIDs: linkedTaskIDs, linkedListIDs: linkedListIDs)
      return true
    }
  }

  /// Upsert one imported daily review (a singleton per `date`) and finish the
  /// write (link projections, sync envelope, changelog), inside the caller's
  /// transaction. Shared by ``importDailyReview`` (overwrite-on-reimport) and
  /// ``importDailyReviewIfAbsent`` (skip-if-present/tombstoned); the latter guards
  /// the date before calling, so its upsert path only ever inserts. Import is a
  /// trust boundary, so the free-text fields are scrubbed here (the sync-apply
  /// path is byte-exact); it is exempt from the interactive staleness window (a
  /// backup legitimately carries reviews older than the interactive write band).
  func writeImportedDailyReviewInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, date: String, summary: String, mood: Int?,
    energyLevel: Int?, wins: String?, blockers: String?, learnings: String?,
    timezone: String?, updatedAt: String?, linkedTaskIDs: [String]?, linkedListIDs: [String]?
  ) throws -> DailyReviewEntry {
    let resolved = try Self.canonicalReviewDate(date)
    let resolvedTaskIDs = try Self.canonicalImportedEntityIDs(
      linkedTaskIDs ?? [], kind: .task, field: "daily review linkedTaskIDs")
    let resolvedListIDs = try Self.canonicalImportedEntityIDs(
      linkedListIDs ?? [], kind: .list, field: "daily review linkedListIDs")
    let resolvedTimezone = try timezone?.nilIfReviewBlank
      ?? WorkflowTimezone.activeTimezoneName(db)
      ?? TimeZone.current.identifier
    let now = try Self.canonicalImportTimestamp(
      updatedAt, field: "daily review updatedAt", fallback: SyncTimestampFormat.syncTimestampNow())
    // Import is local authoring: it rides syncUpsertDailyReview only for its
    // historical-date semantics, so the local text budgets still apply — a
    // restored review can never exceed what the app itself could have written.
    try DailyReviewOpsRepo.validateReviewTextBudgets(
      summary: summary, wins: wins, blockers: blockers, learnings: learnings)
    let applied = try DailyReviewOpsRepo.syncUpsertDailyReview(
      db,
      date: resolved,
      summary: DailyReviewOpsRepo.scrubReviewText(summary),
      mood: mood.map(Int64.init),
      energyLevel: energyLevel.map(Int64.init),
      wins: DailyReviewOpsRepo.scrubReviewText(wins),
      blockers: DailyReviewOpsRepo.scrubReviewText(blockers),
      learnings: DailyReviewOpsRepo.scrubReviewText(learnings),
      timezone: resolvedTimezone,
      version: hlc.nextVersionString(),
      createdAt: now,
      updatedAt: now,
      versionCmp: ">")
    try DailyReviewOpsRepo.requireDailyReviewWriteApplied(applied, date: resolved)
    return try Self.finishDailyReviewWrite(
      db, service: self, hlc: hlc, deviceId: deviceId, date: resolved,
      operation: SyncNaming.opUpsert,
      linkedTaskIds: resolvedTaskIDs,
      linkedListIds: resolvedListIDs)
  }

  public func amendDailyReview(date: String, patch: DailyReviewPatch) async throws
    -> DailyReviewEntry
  {
    try withWrite { db, hlc, deviceId in
      guard try DailyReviewOpsRepo.getDailyReviewRow(db, date: date) != nil else {
        throw LorvexCoreError.unsupportedOperation("No daily review exists for '\(date)' to amend.")
      }
      let timezone =
        try WorkflowTimezone.activeTimezoneName(db) ?? TimeZone.current.identifier
      let params = AmendDailyReviewParams(
        date: date, summary: patch.summary, mood: patch.mood.map(Int64.init),
        energyLevel: patch.energyLevel.map(Int64.init), wins: patch.wins,
        blockers: patch.blockers, learnings: patch.learnings,
        timezoneBackfill: timezone, version: hlc.nextVersionString(),
        now: SyncTimestampFormat.syncTimestampNow())
      let applied = try DailyReviewOpsRepo.amendDailyReview(db, params: params)
      try DailyReviewOpsRepo.requireDailyReviewWriteApplied(applied, date: date)
      // Link projections are only re-materialized when the patch carried them;
      // an absent (nil) set preserves the existing links.
      return try Self.finishDailyReviewWrite(
        db, service: self, hlc: hlc, deviceId: deviceId, date: date, operation: "update",
        linkedTaskIds: patch.linkedTaskIDs, linkedListIds: patch.linkedListIDs)
    }
  }

  // MARK: - Weekly review

  public func loadWeeklyReview() async throws -> WeeklyReviewSnapshot {
    try read { db in
      let snapshot = try WeeklyReview.loadWeeklyReviewSnapshot(db, limits: Self.snapshotLimits)
      return SwiftLorvexReviewDeserializers.weeklyReview(snapshot)
    }
  }

  /// `weekOf` anchors the 7-day window's final day (any valid `YYYY-MM-DD`);
  /// `nil` keeps the trailing window ending today. The MCP tool advertises
  /// "any week", so an ignored anchor would silently hand the assistant the
  /// wrong week's numbers.
  public func getWeeklyReviewSnapshot(weekOf: String?) async throws -> WeeklyReviewSnapshot {
    guard let weekOf else { return try await loadWeeklyReview() }
    let anchor = try Self.canonicalReviewDate(weekOf)
    return try read { db in
      let snapshot = try WeeklyReview.loadWeeklyReviewSnapshot(
        db, limits: Self.snapshotLimits, endingOn: anchor)
      return SwiftLorvexReviewDeserializers.weeklyReview(snapshot)
    }
  }

  public func loadDaySummary(date: String, completedLimit: Int) async throws -> DayReviewSummary {
    let anchor = try Self.canonicalReviewDate(date)
    let limit = UInt32(min(max(completedLimit, 1), 50))
    return try read { db in
      let summary = try DayReview.loadDaySummary(db, date: anchor, completedLimit: limit)
      return DayReviewSummary(
        date: summary.date,
        completedCount: Int(summary.completedCount),
        topCompleted: summary.topCompleted.map {
          ReviewTaskSummary(
            id: $0.id, title: $0.title, status: $0.status, deferCount: Int($0.deferCount))
        },
        createdCount: Int(summary.createdCount),
        dueOpenCount: Int(summary.dueOpenCount),
        habitsCompleted: Int(summary.habitsCompleted),
        habitsTotal: Int(summary.habitsTotal),
        eventCount: Int(summary.eventCount))
    }
  }

  public func getWeeklyReviewBrief(
    completedLimit: Int?,
    stalledListsLimit: Int?,
    deferredLimit: Int?,
    somedayLimit: Int?
  ) async throws -> WeeklyReviewBriefModel {
    let limits = WeeklyReview.BriefLimits(
      completedThisWeek: UInt32(
        WeeklyReviewBriefLimitPolicy.bounded(
          completedLimit, default: WeeklyReviewBriefLimitPolicy.completedDefault)),
      stalledLists: UInt32(
        WeeklyReviewBriefLimitPolicy.bounded(
          stalledListsLimit, default: WeeklyReviewBriefLimitPolicy.stalledDefault)),
      frequentlyDeferred: UInt32(
        WeeklyReviewBriefLimitPolicy.bounded(
          deferredLimit, default: WeeklyReviewBriefLimitPolicy.deferredDefault)),
      somedayItems: UInt32(
        WeeklyReviewBriefLimitPolicy.bounded(
          somedayLimit, default: WeeklyReviewBriefLimitPolicy.somedayDefault)))
    return try read { db in
      SwiftLorvexReviewDeserializers.weeklyReviewBrief(
        try WeeklyReview.loadWeeklyReviewBrief(db, limits: limits))
    }
  }

  // MARK: - Helpers

  /// The MCP snapshot section caps (top_completed / stalled_lists /
  /// frequently_deferred / someday_items) used by the public weekly-review
  /// contract.
  private static let snapshotLimits = WeeklyReview.SnapshotLimits(
    topCompleted: 5, stalledLists: 3, frequentlyDeferred: 5, somedayItems: 5)

  /// Format-only date validation for the import path: any valid calendar date
  /// is accepted, with no staleness/future window.
  private static func canonicalReviewDate(_ value: String) throws -> String {
    guard case .success(let ymd) = IsoDate.parseIsoDate(value) else {
      throw LorvexCoreError.unsupportedOperation(
        "daily review date '\(value)' is not a valid YYYY-MM-DD calendar date")
    }
    return ymd.canonicalString
  }

  private static func resolveReviewDate(_ db: Database, requestedDate: String?) throws -> String {
    let today = try WorkflowTimezone.todayYmdForConn(db)
    switch DailyReviewDate.resolveDailyReviewWriteDate(requestedDate: requestedDate, today: today) {
    case .success(let resolved): return resolved
    case .failure(let error):
      throw LorvexCoreError.validation(field: "date", message: error.description)
    }
  }

  /// Re-materialize the daily-review link tables (when provided), write the
  /// changelog row, and re-read the enriched row to return.
  private static func finishDailyReviewWrite(
    _ db: Database,
    service: SwiftLorvexCoreService,
    hlc: HlcSession,
    deviceId: String,
    date: String,
    operation: String,
    initiatedBy: String? = nil,
    linkedTaskIds: [String]? = nil,
    linkedListIds: [String]? = nil
  ) throws -> DailyReviewEntry {
    try DailyReviewOpsRepo.validateLocalReviewLinkCounts(
      taskIds: linkedTaskIds, listIds: linkedListIds)
    if let linkedTaskIds {
      try DailyReviewOpsRepo.materializeReviewTaskLinks(db, date: date, taskIds: linkedTaskIds)
    }
    if let linkedListIds {
      try DailyReviewOpsRepo.materializeReviewListLinks(db, date: date, listIds: linkedListIds)
    }
    guard let row = try DailyReviewOpsRepo.getDailyReviewRow(db, date: date) else {
      throw StoreError.notFound(entity: EntityName.dailyReview, id: date)
    }
    try service.enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .dailyReview, entityId: date)
    try service.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: operation, entityType: EntityName.dailyReview, entityId: date,
        summary: "Daily review for \(date)", initiatedBy: initiatedBy),
      deviceId: deviceId)
    return SwiftLorvexReviewDeserializers.dailyReview(row)
  }
}

private extension String {
  var nilIfReviewBlank: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }
}
