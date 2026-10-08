import Foundation
import LorvexCore
import LorvexDomain
import LorvexMobile
import Testing

func unsupportedStubCoreOperation() -> LorvexCoreError { .unsupportedOperation("stub") }

extension StubCoreService {
  func loadTask(id: LorvexTask.ID) async throws -> LorvexTask {
    if let task = loadTaskOverride {
      await loadTaskGate?()
      return task
    }
    return try await preview.loadTask(id: id)
  }
  func addTaskChecklistItem(taskID: LorvexTask.ID, text: String) async throws -> LorvexTask {
    try await preview.addTaskChecklistItem(taskID: taskID, text: text)
  }
  func updateTaskChecklistItem(itemID: TaskChecklistItem.ID, text: String) async throws
    -> LorvexTask
  {
    try await preview.updateTaskChecklistItem(itemID: itemID, text: text)
  }
  func toggleTaskChecklistItem(itemID: TaskChecklistItem.ID, completed: Bool) async throws
    -> LorvexTask
  {
    try await preview.toggleTaskChecklistItem(itemID: itemID, completed: completed)
  }
  func removeTaskChecklistItem(itemID: TaskChecklistItem.ID) async throws -> LorvexTask {
    try await preview.removeTaskChecklistItem(itemID: itemID)
  }
  func reorderTaskChecklistItems(taskID: LorvexTask.ID, itemIDs: [TaskChecklistItem.ID])
    async throws -> LorvexTask
  {
    try await preview.reorderTaskChecklistItems(taskID: taskID, itemIDs: itemIDs)
  }
  func addTaskReminder(taskID: LorvexTask.ID, reminderAt: String) async throws -> LorvexTask {
    try await preview.addTaskReminder(taskID: taskID, reminderAt: reminderAt)
  }
  func removeTaskReminder(taskID: LorvexTask.ID, reminderID: TaskReminder.ID) async throws
    -> LorvexTask
  {
    try await preview.removeTaskReminder(taskID: taskID, reminderID: reminderID)
  }
  func setTaskAINotes(taskID: LorvexTask.ID, notes: String) async throws -> LorvexTask {
    throw unsupportedStubCoreOperation()
  }
  func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask {
    try await preview.updateTask(
      id: id,
      title: title,
      notes: notes,
      priority: priority,
      estimatedMinutes: estimatedMinutes,
      dueDate: dueDate,
      plannedDate: plannedDate,
      availableFrom: availableFrom,
      tags: tags,
      dependsOn: dependsOn)
  }
  func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID],
    rawInput: String?
  ) async throws -> LorvexTask {
    try await preview.updateTask(
      id: id,
      title: title,
      notes: notes,
      priority: priority,
      estimatedMinutes: estimatedMinutes,
      dueDate: dueDate,
      plannedDate: plannedDate,
      availableFrom: availableFrom,
      tags: tags,
      dependsOn: dependsOn,
      rawInput: rawInput)
  }
  func updateTask(_ draft: TaskUpdateDraft) async throws -> LorvexTask {
    await updateTaskGate?()
    return try await preview.updateTask(draft)
  }
  func markTaskSomeday(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.markTaskSomeday(id: id)
  }
  func proposeDayTimes(date: String) async throws -> DayTimesProposal {
    try await preview.proposeDayTimes(date: date)
  }
  func proposeDayTimes(
    date: String, workingHoursStart: String?, workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> DayTimesProposal {
    try await preview.proposeDayTimes(
      date: date, workingHoursStart: workingHoursStart, workingHoursEnd: workingHoursEnd,
      includeCalendarEvents: includeCalendarEvents)
  }
  func saveDayTimes(date: String, times: [LorvexTaskTime]) async throws -> [LorvexTask] {
    try await preview.saveDayTimes(date: date, times: times)
  }
  func createList(
    name: String, description: String?, color: String?, icon: String?, aiNotes: String?
  ) async throws -> LorvexList {
    throw unsupportedStubCoreOperation()
  }
  func importList(
    id: LorvexList.ID, name: String, description: String?, color: String?, icon: String?,
    aiNotes: String?, archivedAt: String?, position: Int64?
  ) async throws -> LorvexList {
    throw unsupportedStubCoreOperation()
  }
  func moveTask(id: LorvexTask.ID, toListID listID: LorvexList.ID) async throws -> LorvexTask {
    throw unsupportedStubCoreOperation()
  }
  func updateList(
    id: LorvexList.ID,
    name: String?,
    description: Patch<String>,
    color: String?,
    icon: String?,
    aiNotes: String?
  ) async throws -> LorvexList {
    try await preview.updateList(
      id: id,
      name: name,
      description: description,
      color: color,
      icon: icon,
      aiNotes: aiNotes
    )
  }
  func setListAINotes(id: LorvexList.ID, notes: String) async throws -> LorvexList {
    try await preview.setListAINotes(id: id, notes: notes)
  }
  func deleteList(id: LorvexList.ID) async throws { try await preview.deleteList(id: id) }
  func loadArchivedLists() async throws -> ListCatalogSnapshot {
    try await preview.loadArchivedLists()
  }
  func archiveList(id: LorvexList.ID) async throws -> LorvexList {
    try await preview.archiveList(id: id)
  }
  func unarchiveList(id: LorvexList.ID) async throws -> LorvexList {
    try await preview.unarchiveList(id: id)
  }
  func getList(id: LorvexList.ID) async throws -> LorvexList { try await preview.getList(id: id) }
  func getListHealthSnapshot() async throws -> ListHealthSnapshot {
    try await preview.getListHealthSnapshot()
  }
  func listAllTags() async throws -> [String] { try await preview.listAllTags() }
  func renameTag(oldTag: String, newTag: String) async throws {
    try await preview.renameTag(oldTag: oldTag, newTag: newTag)
  }
  func deleteTag(name: String) async throws -> TagDeletionOutcome {
    try await preview.deleteTag(name: name)
  }
  func mergeTags(source: String, target: String) async throws -> TagMergeOutcome {
    try await preview.mergeTags(source: source, target: target)
  }
  func getTasksByTag(tag: String) async throws -> [LorvexTask] {
    try await preview.getTasksByTag(tag: tag)
  }
  func countTasksByTag(tag: String) async throws -> Int {
    try await preview.countTasksByTag(tag: tag)
  }
  func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput, milestoneTarget: Int?
  ) async throws -> LorvexHabit {
    throw unsupportedStubCoreOperation()
  }
  func importHabit(
    id: LorvexHabit.ID, name: String, icon: String?, color: String?, cue: String?,
    frequencyType: String, weekdays: [Int], perPeriodTarget: Int?, dayOfMonth: Int?,
    targetCount: Int, milestoneTarget: Int?, archived: Bool, position: Int64,
    createdAt: String?
  ) async throws -> LorvexHabit {
    throw unsupportedStubCoreOperation()
  }
  func completeHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot {
    throw unsupportedStubCoreOperation()
  }
  func uncompleteHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot {
    throw unsupportedStubCoreOperation()
  }
  func adjustHabitCompletion(id: LorvexHabit.ID, date: String, delta: Int) async throws
    -> HabitCatalogSnapshot
  {
    throw unsupportedStubCoreOperation()
  }
  func updateHabit(
    id: LorvexHabit.ID,
    name: String?,
    cue: Patch<String>,
    color: String?,
    icon: String?,
    targetCount: Int?,
    archived: Bool?,
    cadence: HabitCadenceInput?,
    milestoneTarget: Patch<Int>
  ) async throws -> LorvexHabit {
    try await preview.updateHabit(
      id: id,
      name: name,
      cue: cue,
      color: color,
      icon: icon,
      targetCount: targetCount,
      archived: archived,
      cadence: cadence,
      milestoneTarget: milestoneTarget
    )
  }
  func deleteHabit(id: LorvexHabit.ID) async throws -> HabitCatalogSnapshot {
    try await preview.deleteHabit(id: id)
  }
  func getHabitCompletions(id: LorvexHabit.ID, from: String?, to: String?, limit: Int) async throws
    -> HabitCompletionsSnapshot
  {
    try await preview.getHabitCompletions(id: id, from: from, to: to, limit: limit)
  }
  func getHabitStats(id: LorvexHabit.ID) async throws -> HabitStats {
    try await preview.getHabitStats(id: id)
  }
  func batchCompleteHabits(ids: [LorvexHabit.ID], date: String) async throws
    -> HabitCatalogSnapshot
  {
    try await preview.batchCompleteHabits(ids: ids, date: date)
  }
  func getHabitReminderPolicies(id: LorvexHabit.ID) async throws -> [HabitReminderPolicy] {
    try await preview.getHabitReminderPolicies(id: id)
  }
  func getAllHabitReminderPolicies() async throws -> [HabitReminderPolicy] {
    try await preview.getAllHabitReminderPolicies()
  }
  func getDueHabitReminderOccurrences(now: Date, horizonDays: Int, deviceZone: TimeZone) async throws
    -> [DueHabitReminderOccurrence]
  {
    if let dueHabitReminderOccurrencesError {
      throw dueHabitReminderOccurrencesError
    }
    return try await preview.getDueHabitReminderOccurrences(
      now: now, horizonDays: horizonDays, deviceZone: deviceZone)
  }
  func reconcileDeliveredHabitReminders(asOf: Date, deviceZone: TimeZone) async throws {
    try await preview.reconcileDeliveredHabitReminders(asOf: asOf, deviceZone: deviceZone)
  }
  func replaceArmedHabitReminders(
    armedThroughByPolicyID: [String: Date], asOf: Date
  ) async throws {
    try await preview.replaceArmedHabitReminders(
      armedThroughByPolicyID: armedThroughByPolicyID, asOf: asOf)
  }

  func deleteHabitReminderPolicy(policyID: String) async throws -> HabitReminderPolicy? {
    try await preview.deleteHabitReminderPolicy(policyID: policyID)
  }
  func upsertHabitReminderPolicy(id: LorvexHabit.ID, policy: HabitReminderPolicy)
    async throws -> HabitReminderPolicy
  {
    try await preview.upsertHabitReminderPolicy(id: id, policy: policy)
  }
  func createCalendarEvent(
    title: String, startDate: String, endDate: String?, startTime: String?, endTime: String?,
    allDay: Bool, location: String?, notes: String?, recurrence: TaskRecurrenceRule?,
    timezone: String?,
    url: String?, color: String?, eventType: String?, personName: String?,
    attendees: [CalendarEventAttendee]?
  ) async throws -> CalendarTimelineEvent {
    throw unsupportedStubCoreOperation()
  }
  func batchCreateCalendarEvents(_ drafts: [CalendarEventCreateDraft]) async throws
    -> [CalendarTimelineEvent]
  {
    throw unsupportedStubCoreOperation()
  }
  func updateCalendarEvent(
    id: CalendarTimelineEvent.ID, title: String?, startDate: String?, endDate: String?,
    startTime: String?, endTime: String?, allDay: Bool?, location: String?, notes: String?,
    recurrence: CalendarEventRecurrencePatch, timezone: String?, url: String?, color: String?,
    eventType: String?,
    personName: String?, attendees: CalendarEventAttendeesPatch
  ) async throws -> CalendarTimelineEvent {
    throw unsupportedStubCoreOperation()
  }
  func importCalendarEvent(
    id: CalendarTimelineEvent.ID, title: String, startDate: String, startTime: String?,
    endDate: String?, endTime: String?, allDay: Bool, location: String?, notes: String?,
    url: String?, color: String?, eventType: String?, personName: String?,
    attendees: [CalendarEventAttendee]?, timezone: String?, recurrence: String?,
    seriesId: String?, recurrenceInstanceDate: String?, occurrenceState: String?,
    recurrenceGeneration: String?, seriesCutoverId: String?
  ) async throws -> CalendarTimelineEvent {
    throw unsupportedStubCoreOperation()
  }
  @discardableResult
  func deleteCalendarEvent(id: CalendarTimelineEvent.ID) async throws -> CalendarTimelineEvent? {
    throw unsupportedStubCoreOperation()
  }
  func searchCalendarEvents(query: String, from: String?, to: String?, limit: Int?, offset: Int)
    async throws -> [CalendarTimelineEvent]
  {
    throw unsupportedStubCoreOperation()
  }
  func linkTaskToProviderEvent(
    taskID: LorvexTask.ID, providerEventID: String, providerSource: String
  ) async throws -> TaskCalendarEventLink {
    throw unsupportedStubCoreOperation()
  }
  @discardableResult
  func unlinkTaskFromProviderEvent(taskID: LorvexTask.ID, providerEventID: String) async throws
    -> Bool
  {
    throw unsupportedStubCoreOperation()
  }
  func getLinkedEventsForTask(taskID: LorvexTask.ID) async throws -> [CalendarTimelineEvent] {
    throw unsupportedStubCoreOperation()
  }
  func getLinkedTasksForEvent(eventID: CalendarTimelineEvent.ID) async throws -> [LorvexTask] {
    throw unsupportedStubCoreOperation()
  }
  func exportCalendarICS(from: String?, to: String?) async throws -> String {
    throw unsupportedStubCoreOperation()
  }
  func upsertMemory(key: String, content: String) async throws -> MemoryEntry {
    throw unsupportedStubCoreOperation()
  }
  func deleteMemory(key: String) async throws -> Bool { try await preview.deleteMemory(key: key) }

  func importRemoteTask(
    id: LorvexTask.ID, title: String, notes: String, aiNotes: String?,
    rawInput: String?, priority: LorvexTask.Priority,
    status: LorvexTask.Status, estimatedMinutes: Int?, dueDate: Date?, plannedDate: Date?,
    availableFrom: Date?,
    tags: [String], dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask { throw unsupportedStubCoreOperation() }

  func setTaskRecurrence(taskID: LorvexTask.ID, rule: TaskRecurrenceRule) async throws -> LorvexTask
  {
    setTaskRecurrenceCallCount += 1
    return try await preview.setTaskRecurrence(taskID: taskID, rule: rule)
  }
  func removeTaskRecurrence(taskID: LorvexTask.ID) async throws -> LorvexTask {
    removeTaskRecurrenceCallCount += 1
    return try await preview.removeTaskRecurrence(taskID: taskID)
  }
  func addTaskRecurrenceException(taskID: LorvexTask.ID, exceptionDate: String) async throws
    -> LorvexTask
  {
    throw unsupportedStubCoreOperation()
  }
  func removeTaskRecurrenceException(taskID: LorvexTask.ID, exceptionDate: String) async throws
    -> LorvexTask
  {
    throw unsupportedStubCoreOperation()
  }
  func batchCompleteTasks(ids: [LorvexTask.ID]) async throws -> TaskBatchLifecycleResult {
    batchCompleteTaskCallCount += 1
    if batchTaskDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: batchTaskDelayNanoseconds)
    }
    return try await preview.batchCompleteTasks(ids: ids)
  }
  func batchReopenTasks(ids: [LorvexTask.ID]) async throws -> TaskBatchLifecycleResult {
    if batchTaskDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: batchTaskDelayNanoseconds)
    }
    return try await preview.batchReopenTasks(ids: ids)
  }
  func batchMoveTasks(ids: [LorvexTask.ID], toListID listID: LorvexList.ID) async throws
    -> TaskBatchMoveResult
  {
    throw unsupportedStubCoreOperation()
  }
  func batchDeferTasks(ids: [LorvexTask.ID], until date: Date, reason: String?, note: String?)
    async throws -> TaskBatchLifecycleResult
  {
    if batchTaskDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: batchTaskDelayNanoseconds)
    }
    return try await preview.batchDeferTasks(ids: ids, until: date, reason: reason, note: note)
  }
  func appendToTaskBody(taskID: LorvexTask.ID, additionalNotes: String) async throws -> LorvexTask {
    throw unsupportedStubCoreOperation()
  }
  func setTaskReminders(taskID: LorvexTask.ID, reminderAts: [String]) async throws -> LorvexTask {
    throw unsupportedStubCoreOperation()
  }
  func getDependencyGraph(rootTaskID: LorvexTask.ID?, listID: LorvexList.ID?, includeInactive: Bool)
    async throws -> DependencyGraph
  {
    throw unsupportedStubCoreOperation()
  }
  func getUpcomingTasks(daysAhead: Int, limit: Int) async throws -> [LorvexTask] {
    throw unsupportedStubCoreOperation()
  }
  func getUpcomingTaskPage(daysAhead: Int, limit: Int, offset: Int) async throws -> TaskPageResult
  {
    throw unsupportedStubCoreOperation()
  }
  func getDueTaskReminders(asOf: String?, limit: Int) async throws -> [TaskReminderWithTask] {
    throw unsupportedStubCoreOperation()
  }
  func markDueTaskRemindersDelivered(asOf: Date) async throws -> Int {
    try await preview.markDueTaskRemindersDelivered(asOf: asOf)
  }
  func replaceArmedTaskReminders(reminderIDs: [String], asOf: Date) async throws {
    try await preview.replaceArmedTaskReminders(reminderIDs: reminderIDs, asOf: asOf)
  }
  func getUpcomingTaskReminders(hoursAhead: Int, limit: Int) async throws -> [TaskReminderWithTask]
  { throw unsupportedStubCoreOperation() }

  func amendDailyReview(date: String, patch: DailyReviewPatch) async throws -> DailyReviewEntry {
    try await preview.amendDailyReview(date: date, patch: patch)
  }
  func getReviewHistory(from: String?, to: String?, limit: Int?) async throws
    -> [DailyReviewEntry]
  {
    try await preview.getReviewHistory(from: from, to: to, limit: limit)
  }
  func getWeeklyReviewSnapshot(weekOf: String?) async throws -> WeeklyReviewSnapshot {
    if let loadWeeklyReviewError {
      throw loadWeeklyReviewError
    }
    return try await preview.getWeeklyReviewSnapshot(weekOf: weekOf)
  }
  func getWeeklyReviewBrief(
    completedLimit: Int?, stalledListsLimit: Int?, deferredLimit: Int?, somedayLimit: Int?
  ) async throws -> WeeklyReviewBriefModel {
    try await preview.getWeeklyReviewBrief(
      completedLimit: completedLimit, stalledListsLimit: stalledListsLimit,
      deferredLimit: deferredLimit, somedayLimit: somedayLimit)
  }

  func loadAIChangelog(
    limit: Int?,
    offset: Int?,
    entityType: String?,
    operation: String?,
    entityID: String?,
    since: String?
  ) async throws -> AIChangelogSnapshot {
    try await preview.loadAIChangelog(
      limit: limit,
      offset: offset,
      entityType: entityType,
      operation: operation,
      entityID: entityID,
      since: since
    )
  }

  func loadRecentLogs(
    limit: Int, offset: Int, since: String?, levels: [String]?, sources: [String]?, redact: Bool
  ) async throws -> RecentLogsPage {
    try await preview.loadRecentLogs(
      limit: limit, offset: offset, since: since, levels: levels, sources: sources, redact: redact)
  }
  func appendDiagnosticLog(
    source: String, level: String, message: String, details: String?
  ) async throws {
    try await preview.appendDiagnosticLog(
      source: source, level: level, message: message, details: details)
  }
  func getAllPreferences() async throws -> PreferencesSnapshot {
    try await preview.getAllPreferences()
  }
  func getPreference(key: String) async throws -> String? {
    try await preview.getPreference(key: key)
  }
  func setPreference(key: String, value: String) async throws -> String {
    try await preview.setPreference(key: key, value: value)
  }
  func completeSetup(workingHours: String?, defaultListID: String?, timezone: String?)
    async throws -> PreferencesSnapshot
  {
    try await preview.completeSetup(
      workingHours: workingHours,
      defaultListID: defaultListID,
      timezone: timezone
    )
  }
  func getOverviewCompact() async throws -> OverviewCompactSnapshot {
    try await preview.getOverviewCompact()
  }
  func loadOverviewTaskList() async throws -> OverviewTaskListSnapshot {
    if let loadOverviewTaskListError { throw loadOverviewTaskListError }
    return try await preview.loadOverviewTaskList()
  }
  func getSessionContext() async throws -> SessionContextSnapshot {
    try await preview.getSessionContext()
  }
  func recordAssistantActivity(clientName: String, clientTitle: String?, clientVersion: String?)
    async throws
  {
    try await preview.recordAssistantActivity(
      clientName: clientName, clientTitle: clientTitle, clientVersion: clientVersion)
  }
  func loadAssistantSessions() async throws -> [AssistantSessionRecord] {
    try await preview.loadAssistantSessions()
  }
}
