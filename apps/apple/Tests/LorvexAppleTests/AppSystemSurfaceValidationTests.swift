import Foundation
import LorvexCore
import LorvexDomain
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func systemIntentRunnerRejectsBlankDailyReviewSummary() async {
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.saveDailyReview(
      summary: "   ",
      date: nil,
      mood: nil,
      energyLevel: nil,
      wins: nil,
      blockers: nil,
      learnings: nil,
      core: try await makeSeededInMemoryCore()
    )
  }
}

@Test
func systemIntentRunnerRejectsInvalidReviewQueries() async {
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.amendDailyReview(
      date: "   ",
      summary: "Updated",
      mood: nil,
      energyLevel: nil,
      wins: nil,
      blockers: nil,
      learnings: nil,
      core: try await makeSeededInMemoryCore()
    )
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.readReviewHistory(
      from: nil,
      to: nil,
      limit: 0,
      core: try await makeSeededInMemoryCore()
    )
  }
}

@Test
func systemIntentRunnerRejectsInvalidPreferences() async {
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.readPreference(
      key: "   ",
      core: try await makeSeededInMemoryCore()
    )
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.setPreference(
      key: "theme",
      value: "   ",
      core: try await makeSeededInMemoryCore()
    )
  }
}

/// FIX 2: the App-Intents `set_preference` / `delete_preference` surface must
/// mirror the MCP host's allowlist. An arbitrary key is rejected before any DB
/// work — it would otherwise persist a `preferences` row and enqueue a sync
/// envelope every peer rejects (`SyncEntityId.validatePreference`), permanently
/// diverging devices.
@Test
func systemIntentRunnerRejectsUnknownWritablePreferenceKey() async throws {
  let core = try await makeSeededInMemoryCore()
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.setPreference(
      key: "totally_unknown_key", value: "malicious", core: core)
  }
  await #expect(throws: LorvexCoreError.self) {
    try await LorvexSystemIntentRunner.deletePreference(
      key: "totally_unknown_key", core: core)
  }
  // Rejected before reaching the core: nothing was written.
  let stored = try await LorvexSystemIntentRunner.readPreference(
    key: "totally_unknown_key", core: core)
  #expect(stored == nil)
}

/// The device-local calendar AI-access tier is the allowlist's special case
/// (it is not one of the synced `pref*` keys) and must still be writable /
/// deletable — that is the App-Intents path by which a privacy downgrade
/// reaches the core purge.
@Test
func systemIntentRunnerAllowsCalendarAccessModeWriteAndDelete() async throws {
  let core = try await makeSeededInMemoryCore()
  let value = try await LorvexSystemIntentRunner.setPreference(
    key: PreferenceKeys.devCalendarAiAccessMode,
    value: CalendarAiAccessMode.busyOnly.asString,
    core: core)
  #expect(value == CalendarAiAccessMode.busyOnly.asString)
  try await LorvexSystemIntentRunner.deletePreference(
    key: PreferenceKeys.devCalendarAiAccessMode, core: core)
}

@Test
func systemIntentRunnerRejectsBlankMemoryFields() async {
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.saveMemory(
      key: "   ",
      content: "Memory",
      core: try await makeSeededInMemoryCore()
    )
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.saveMemory(
      key: "shortcut_context",
      content: "   ",
      core: try await makeSeededInMemoryCore()
    )
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.readMemory(
      key: "   ",
      core: try await makeSeededInMemoryCore()
    )
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.readMemory(
      key: "missing_memory_key",
      core: try await makeSeededInMemoryCore()
    )
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.deleteMemory(
      key: "   ",
      core: try await makeSeededInMemoryCore()
    )
  }
}

/// The Shortcuts/Siri list runner must accept the `in_progress` and
/// `actionable` status filters it previously rejected with "Unsupported task
/// status filter", routing each through the shared core resolver: `in_progress`
/// resolves to the started-only lane, `actionable` to the `open` + `in_progress`
/// working set, and the pre-existing `open` filter stays open-only. An unknown
/// value still throws. Regression guard for the AppEnum offering "In Progress"
/// while the runner rejected it.
@Test
func systemIntentRunnerListTasksAcceptsInProgressAndActionableFilters() async throws {
  let core = try makeInMemoryCore()
  let openTask = try await core.createTask(title: "Open task", notes: "")
  let startedTask = try await core.createTask(title: "Started task", notes: "")
  _ = try await core.startTaskReturningTask(id: startedTask.id)

  let inProgress = try await LorvexSystemIntentRunner.listTasks(
    status: "in_progress", listID: nil, priority: nil, text: nil, limit: nil, offset: nil,
    core: core)
  #expect(inProgress.tasks.map(\.id) == [startedTask.id])

  let actionable = try await LorvexSystemIntentRunner.listTasks(
    status: "actionable", listID: nil, priority: nil, text: nil, limit: nil, offset: nil,
    core: core)
  #expect(Set(actionable.tasks.map(\.id)) == [openTask.id, startedTask.id])

  let openOnly = try await LorvexSystemIntentRunner.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: nil, offset: nil, core: core)
  #expect(openOnly.tasks.map(\.id) == [openTask.id])

  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.listTasks(
      status: "bogus", listID: nil, priority: nil, text: nil, limit: nil, offset: nil, core: core)
  }
}

/// The sibling `searchTasks` status validation gained the same `in_progress` /
/// `actionable` acceptance, resolving through the core search-status resolver
/// (`in_progress` → started-only, `actionable` → `open` + `in_progress`). An
/// unknown value still throws.
@Test
func systemIntentRunnerSearchTasksAcceptsInProgressAndActionableFilters() async throws {
  let core = try makeInMemoryCore()
  let openTask = try await core.createTask(title: "Searchable alpha", notes: "")
  let startedTask = try await core.createTask(title: "Searchable beta", notes: "")
  _ = try await core.startTaskReturningTask(id: startedTask.id)

  let inProgress = try await LorvexSystemIntentRunner.searchTasks(
    query: "Searchable", status: "in_progress", limit: nil, offset: nil, core: core)
  #expect(inProgress.tasks.map(\.id) == [startedTask.id])

  let actionable = try await LorvexSystemIntentRunner.searchTasks(
    query: "Searchable", status: "actionable", limit: nil, offset: nil, core: core)
  #expect(Set(actionable.tasks.map(\.id)) == [openTask.id, startedTask.id])

  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.searchTasks(
      query: "Searchable", status: "bogus", limit: nil, offset: nil, core: core)
  }
}

@Test
func taskIntentRunnerValidatesTaskIDsForOpenTaskIntents() throws {
  #expect(try LorvexTaskIntentRunner.validatedTaskID(" task-123 ") == "task-123")
  #expect(throws: LorvexCoreError.self) {
    try LorvexTaskIntentRunner.validatedTaskID("  ")
  }
}

@Test
func taskEntityQueryMapsAndSearchesOpenCoreTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Shortcut entity lookup", notes: "")
  _ = try await core.createTask(title: "Unrelated entity task", notes: "")

  let entity = try await LorvexTaskEntityQuery.entity(id: created.id, core: core)
  #expect(entity.id == created.id)
  #expect(entity.title == "Shortcut entity lookup")
  #expect(entity.status == "open")

  let matches = try await LorvexTaskEntityQuery.entities(matching: "lookup", core: core)
  #expect(matches.map(\.id) == [created.id])

  _ = try await core.completeTask(id: created.id)
  let suggested = try await LorvexTaskEntityQuery.suggestedEntities(core: core)
  #expect(!suggested.contains { $0.id == created.id })
}

/// `entities(matching:)` routes through the core's full-corpus `searchTasks`
/// (FTS/fallback) rather than substring-filtering today's snapshot, so a task
/// whose query term appears only in its notes (never surfaced on the entity)
/// is found. Completed/cancelled matches stay excluded via the active-task
/// post-filter. Regression guard for audit finding H-10.
@Test
func taskEntityQuerySearchesNotesAndExcludesInactiveTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let withNotes = try await core.createTask(
    title: "Plan the offsite", notes: "remember to book the kayak rental")
  let done = try await core.createTask(title: "Kayak deposit", notes: "")
  _ = try await core.completeTask(id: done.id)

  let matches = try await LorvexTaskEntityQuery.entities(matching: "kayak", core: core)
  #expect(matches.map(\.id) == [withNotes.id])
}

@Test
func taskEntityQuerySuggestionsUseFullCorpusInsteadOfTodaySnapshot() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  core.loadTodayError = .unsupportedOperation("loadToday must not feed App Intent task suggestions")
  let offscreen = try await core.createTask(title: "Offscreen shortcut suggestion", notes: "")

  let suggested = try await LorvexTaskEntityQuery.suggestedEntities(core: core)

  #expect(suggested.contains { $0.id == offscreen.id })
}
