import Foundation
import LorvexCore
import LorvexMobile
import Testing

extension StubFocusCoreService {
  func loadFocusSchedule(date: String) async throws -> FocusSchedule? {
    try await preview.loadFocusSchedule(date: date)
  }
  func loadFocusScheduleForAI(date: String) async throws -> FocusSchedule? {
    try await preview.loadFocusScheduleForAI(date: date)
  }
  func loadLists() async throws -> ListCatalogSnapshot {
    loadListsCallCount += 1
    if let loadListsError {
      throw loadListsError
    }
    return try await preview.loadLists()
  }
  func loadListDetail(id: LorvexList.ID, limit: Int, offset: Int) async throws -> ListDetailSnapshot {
    try await preview.loadListDetail(id: id, limit: limit, offset: offset)
  }
  func loadHabits(date: String) async throws -> HabitCatalogSnapshot {
    loadHabitsCallCount += 1
    return try await preview.loadHabits(date: date)
  }
  func reorderLists(orderedIDs: [LorvexList.ID]) async throws -> ListCatalogSnapshot {
    try await preview.reorderLists(orderedIDs: orderedIDs)
  }
  func reorderHabits(orderedIDs: [LorvexHabit.ID], date: String) async throws
    -> HabitCatalogSnapshot
  {
    try await preview.reorderHabits(orderedIDs: orderedIDs, date: date)
  }
  func loadCalendarTimeline(from: String, to: String) async throws -> CalendarTimelineSnapshot {
    loadCalendarTimelineCallCount += 1
    return try await preview.loadCalendarTimeline(from: from, to: to)
  }
  func getCalendarEvent(id: CalendarTimelineEvent.ID) async throws -> CalendarTimelineEvent? {
    try await preview.getCalendarEvent(id: id)
  }
  func getCalendarEventForExternalProjection(
    id: CalendarTimelineEvent.ID
  ) async throws -> CalendarTimelineEvent? {
    try await preview.getCalendarEventForExternalProjection(id: id)
  }
  func loadDailyReview(date: String?) async throws -> DailyReviewEntry? {
    try await preview.loadDailyReview(date: date)
  }
  func loadDaySummary(date: String, completedLimit: Int) async throws -> DayReviewSummary {
    try await preview.loadDaySummary(date: date, completedLimit: completedLimit)
  }
  func importDailyReview(
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
  ) async throws -> DailyReviewEntry {
    try await preview.importDailyReview(
      date: date,
      summary: summary,
      mood: mood,
      energyLevel: energyLevel,
      wins: wins,
      blockers: blockers,
      learnings: learnings,
      timezone: timezone,
      updatedAt: updatedAt,
      linkedTaskIDs: linkedTaskIDs,
      linkedListIDs: linkedListIDs
    )
  }
  func upsertDailyReview(
    date: String?, summary: String, mood: Int?, energyLevel: Int?, wins: String?,
    blockers: String?, learnings: String?, linkedTaskIDs: [String], linkedListIDs: [String]
  ) async throws -> DailyReviewEntry {
    try await preview.upsertDailyReview(
      date: date,
      summary: summary,
      mood: mood,
      energyLevel: energyLevel,
      wins: wins,
      blockers: blockers,
      learnings: learnings,
      linkedTaskIDs: linkedTaskIDs,
      linkedListIDs: linkedListIDs
    )
  }
  func upsertDailyReviewPreservingLinks(
    date: String?, summary: String, mood: Int?, energyLevel: Int?, wins: String?,
    blockers: String?, learnings: String?
  ) async throws -> DailyReviewEntry {
    try await preview.upsertDailyReviewPreservingLinks(
      date: date, summary: summary, mood: mood, energyLevel: energyLevel,
      wins: wins, blockers: blockers, learnings: learnings)
  }
  func loadMemory() async throws -> MemorySnapshot {
    loadMemoryCallCount += 1
    return try await preview.loadMemory()
  }
  func loadRuntimeDiagnostics() async throws -> RuntimeDiagnosticsSnapshot {
    loadRuntimeDiagnosticsCallCount += 1
    if let loadRuntimeDiagnosticsError {
      throw loadRuntimeDiagnosticsError
    }
    return try await preview.loadRuntimeDiagnostics()
  }

  // MARK: Data-export reads — delegated so a test exercising export through
  // this stub gets the same complete categories as the backing core, rather
  // than a stub-specific hole.
  func loadTasksForDataExport() async throws -> [ExportTask] {
    try await preview.loadTasksForDataExport()
  }

  func loadTaskExportBundleForDataExport() async throws -> TaskDataExportBundle {
    try await preview.loadTaskExportBundleForDataExport()
  }
  func loadTagsForDataExport() async throws -> [ExportTag] {
    try await preview.loadTagsForDataExport()
  }
  func loadCalendarEventsForDataExport() async throws -> [ExportCalendarEvent] {
    try await preview.loadCalendarEventsForDataExport()
  }
  func loadCalendarBundleForDataExport() async throws -> ExportCalendarBundle {
    try await preview.loadCalendarBundleForDataExport()
  }
  func loadCurrentFocusForDataExport() async throws -> [ExportCurrentFocus] {
    try await preview.loadCurrentFocusForDataExport()
  }
  func loadFocusSchedulesForDataExport() async throws -> [ExportFocusSchedule] {
    try await preview.loadFocusSchedulesForDataExport()
  }
  func loadFocusSchedulesForAIDataExport() async throws -> [ExportFocusSchedule] {
    try await preview.loadFocusSchedulesForAIDataExport()
  }
  func loadTaskCalendarEventLinksForDataExport() async throws -> [ExportTaskCalendarEventLink] {
    try await preview.loadTaskCalendarEventLinksForDataExport()
  }
  func loadMemoryForDataExport() async throws -> [ExportMemoryEntry] {
    try await preview.loadMemoryForDataExport()
  }
}
