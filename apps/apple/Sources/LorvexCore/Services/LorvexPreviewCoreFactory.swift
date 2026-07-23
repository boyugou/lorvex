import Foundation

/// Builds real in-memory cores pre-populated with the fixed preview dataset
/// (`LorvexPreviewSeedData`): two lists, four tasks (checklist, reminder,
/// recurrence, dependency edges), two habits with completion history, one
/// calendar event, two memory keys, and one daily review.
///
/// The seed is replayed through `SwiftLorvexCoreService`'s own id-preserving
/// import surface plus ordinary writes (`moveTask`, `completeHabit`,
/// `setTaskRecurrence`), so every seeded row carries real store bookkeeping
/// (versions, changelog, sync outbox) and every read reflects the production
/// query semantics — there is no parallel in-memory implementation to drift.
public enum LorvexPreviewCoreFactory {
  /// A seeded real core over an in-memory store. Deterministic fixed-date seed
  /// (2026-05-22) except habit completions, which are seeded relative to today
  /// so `completionsToday` / streaks render as the fixed seed described them.
  public static func makeSeeded() async throws -> SwiftLorvexCoreService {
    let core = try SwiftLorvexCoreService.inMemory()
    try await seed(core)
    return core
  }

  #if DEBUG
    /// `--ui-preview` seed: the fixed seed plus today-relative calendar events so
    /// the Today schedule agenda renders a realistic day, and optionally a saved
    /// focus plan + schedule for today. The canonical import cannot represent the
    /// EventKit provider mirror, so the two events the fake marked
    /// `source: "provider"` seed as Lorvex-owned canonical events here.
    public static func makeUIPreviewSeeded(
      todaySchedule: Bool, focusSchedule: Bool = false
    ) async throws -> SwiftLorvexCoreService {
      let core = try await makeSeeded()
      if todaySchedule {
        for event in LorvexPreviewSeedData.todayPreviewEvents() {
          _ = try await core.importCalendarEvent(
            id: event.id, title: event.title, startDate: event.startDate,
            startTime: event.startTime, endDate: event.endDate, endTime: event.endTime,
            allDay: event.allDay, location: event.location, notes: nil, url: nil,
            color: event.color, eventType: event.eventType, personName: nil,
            attendees: nil, timezone: event.timezone, recurrence: nil,
            seriesId: nil, recurrenceInstanceDate: nil)
        }
      }
      if focusSchedule {
        let (plan, schedule) = LorvexPreviewSeedData.todayPreviewFocus()
        _ = try await core.setCurrentFocus(
          date: plan.date, taskIDs: plan.taskIDs, briefing: plan.briefing,
          timezone: plan.timezone ?? TimeZone.current.identifier)
        _ = try await core.saveFocusSchedule(
          date: schedule.date, blocks: schedule.blocks, rationale: schedule.rationale)
      }
      return core
    }

    /// Synchronous form of ``makeUIPreviewSeeded(todaySchedule:focusSchedule:)``
    /// for launch-time construction (`--ui-preview` builds its `AppStore`
    /// inside the synchronous SwiftUI `App` init). Blocks the calling thread
    /// while the seed replays on the concurrency pool; the service never hops
    /// to the main actor, so the wait cannot deadlock. Traps on a seed
    /// failure — a broken preview dataset is a build defect, not a runtime
    /// condition to recover from.
    public static func makeUIPreviewSeededBlocking(
      todaySchedule: Bool, focusSchedule: Bool = false
    ) -> SwiftLorvexCoreService {
      let box = ResultBox()
      let semaphore = DispatchSemaphore(value: 0)
      Task.detached {
        do {
          box.result = .success(
            try await makeUIPreviewSeeded(
              todaySchedule: todaySchedule, focusSchedule: focusSchedule))
        } catch {
          box.result = .failure(error)
        }
        semaphore.signal()
      }
      semaphore.wait()
      switch box.result {
      case .success(let core):
        return core
      case .failure(let error):
        fatalError("UI-preview seed failed: \(error)")
      case nil:
        fatalError("UI-preview seed signalled without a result.")
      }
    }

    /// Crosses the detached seeding task and the blocked caller; written
    /// exactly once before the semaphore signals.
    private final class ResultBox: @unchecked Sendable {
      var result: Result<SwiftLorvexCoreService, any Error>?
    }
  #endif

  private static func seed(_ core: SwiftLorvexCoreService) async throws {
    // The preview dataset is a synthetic bulk load, not a live user/assistant
    // session, so bind `import` provenance around the whole seed — the same
    // ambient the id-preserving importers inherit under `LorvexDataImporter`.
    // Without it the seed rows would inherit the `user` default and drop out of
    // the assistant-facing ai_changelog surface.
    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.importAttribution
    ) {
      try await seedPreferences(core)
      try await seedLists(core)
      try await seedTasks(core)
      try await seedHabits(core)
      try await seedCalendar(core)
      try await seedMemory(core)
      try await seedReview(core)
    }
  }

  /// The preview environment's preferences. `setup_completed` is `"true"`:
  /// the dataset describes a store in active use, so previews render the
  /// workspaces rather than the setup wizard. (`default_list_id` is already
  /// schema-seeded to the sentinel Inbox.)
  private static let previewPreferences: [String: String] = [
    "working_hours": #"{"start":"09:00","end":"17:00"}"#,
    "timezone": "\"America/Los_Angeles\"",
    "theme": "\"system\"",
    "language": "\"en\"",
    "setup_completed": "true",
  ]

  private static func seedPreferences(_ core: SwiftLorvexCoreService) async throws {
    for (key, value) in previewPreferences.sorted(by: { $0.key < $1.key }) {
      _ = try await core.setPreference(key: key, value: value)
    }
  }

  private static func seedLists(_ core: SwiftLorvexCoreService) async throws {
    for list in LorvexPreviewSeedData.lists.lists {
      _ = try await core.importList(
        id: list.id, name: list.name, description: list.description,
        color: list.color, icon: list.icon)
    }
  }

  /// The seed's non-default list memberships, keyed by task id. Imported tasks
  /// land in the sentinel Inbox (`tasks.list_id` defaults to `'inbox'`), so
  /// only moves elsewhere are replayed — `moveTask` treats a move to the
  /// current list as a skip, not a success.
  private static let taskListIDs: [LorvexTask.ID: LorvexList.ID] = [
    LorvexPreviewSeedID.agendaTask: LorvexPreviewSeedID.appleNativeList,
    LorvexPreviewSeedID.statusUpdateTask: LorvexPreviewSeedID.appleNativeList,
  ]

  private static func seedTasks(_ core: SwiftLorvexCoreService) async throws {
    for task in LorvexPreviewSeedData.tasks {
      _ = try await core.importRemoteTask(
        id: task.id, title: task.title, notes: task.notes, aiNotes: nil, rawInput: nil,
        priority: task.priority, status: task.status,
        estimatedMinutes: task.estimatedMinutes,
        dueDate: nil, plannedDate: nil, availableFrom: nil,
        tags: task.tags, dependsOn: task.dependsOn)
      if let listID = taskListIDs[task.id] {
        _ = try await core.moveTask(id: task.id, toListID: listID)
      }
      for item in task.checklistItems {
        try await core.importTaskChecklistItem(
          taskID: task.id, item: ExportChecklistItem(from: item))
      }
      for reminder in task.reminders {
        try await core.importTaskReminder(
          taskID: task.id, reminder: ExportTaskReminder(from: reminder))
      }
      if let rule = task.recurrence {
        _ = try await core.setTaskRecurrence(taskID: task.id, rule: rule)
      }
    }
  }

  /// Completion counts per habit id: (today, priorDays). Chosen so the derived
  /// stats reproduce the fixed seed's display values (`habit-review`
  /// completionsToday 1 / totalCompletions 12, `habit-plan` 0 / 8).
  private static let habitCompletionCounts: [LorvexHabit.ID: (today: Int, priorDays: Int)] = [
    LorvexPreviewSeedID.dailyReviewHabit: (today: 1, priorDays: 11),
    LorvexPreviewSeedID.eveningWalkHabit: (today: 0, priorDays: 8),
  ]

  private static func seedHabits(_ core: SwiftLorvexCoreService) async throws {
    for (index, habit) in LorvexPreviewSeedData.habits.habits.enumerated() {
      _ = try await core.importHabit(
        id: habit.id, name: habit.name, icon: habit.icon, color: habit.color,
        cue: habit.cue, frequencyType: habit.frequencyType, weekdays: [],
        perPeriodTarget: nil, dayOfMonth: nil, targetCount: habit.targetCount,
        milestoneTarget: nil, archived: habit.archived, position: Int64(index))
      guard let counts = habitCompletionCounts[habit.id] else { continue }
      for _ in 0..<counts.today {
        _ = try await core.completeHabit(id: habit.id, date: ymd(daysAgo: 0))
      }
      for day in stride(from: 1, through: counts.priorDays, by: 1) {
        _ = try await core.completeHabit(id: habit.id, date: ymd(daysAgo: day))
      }
    }
  }

  private static func seedCalendar(_ core: SwiftLorvexCoreService) async throws {
    for event in LorvexPreviewSeedData.calendarEvents.events {
      _ = try await core.importCalendarEvent(
        id: event.id, title: event.title, startDate: event.startDate,
        startTime: event.startTime, endDate: event.endDate, endTime: event.endTime,
        allDay: event.allDay, location: event.location, notes: nil, url: nil,
        color: event.color, eventType: event.eventType, personName: nil,
        attendees: nil, timezone: event.timezone, recurrence: nil,
        seriesId: nil, recurrenceInstanceDate: nil)
    }
  }

  private static func seedMemory(_ core: SwiftLorvexCoreService) async throws {
    for entry in LorvexPreviewSeedData.memory.entries {
      _ = try await core.importMemoryEntry(
        key: entry.key, content: entry.content, updatedAt: entry.updatedAt)
    }
  }

  private static func seedReview(_ core: SwiftLorvexCoreService) async throws {
    for review in LorvexPreviewSeedData.dailyReviews.values {
      _ = try await core.importDailyReview(
        date: review.date, summary: review.summary, mood: review.mood,
        energyLevel: review.energyLevel, wins: review.wins, blockers: review.blockers,
        learnings: review.learnings,
        timezone: review.timezone, updatedAt: review.updatedAt,
        linkedTaskIDs: review.linkedTaskIDs, linkedListIDs: review.linkedListIDs)
    }
  }

  private static func ymd(daysAgo: Int) -> String {
    LorvexDateFormatters.ymd.string(
      from: Date().addingTimeInterval(TimeInterval(-daysAgo) * 86_400))
  }
}
