import Foundation
import GRDB
import LorvexDomain
import LorvexStore

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
  /// `wallClock` is the instant time-of-day reads treat as now. `text`
  /// translates the dataset's user content (titles, notes, names, reviews,
  /// memory); the default seeds it in English, as every test expects.
  public static func makeSeeded(
    wallClock: @escaping @Sendable () -> Date = { Date() },
    text: LorvexSampleText = .english
  ) async throws -> SwiftLorvexCoreService {
    let core = try SwiftLorvexCoreService.inMemory(wallClock: wallClock)
    try await seed(core, text: text)
    return core
  }

  #if DEBUG
    /// The preview run's now: the real clock, or today at the pinned
    /// `-lorvexPreviewNow` time in the seed's timezone, so a schedule proposed
    /// in a capture run starts where that run's Today draws its clock.
    private static let previewWallClock: @Sendable () -> Date = {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: previewTimezone) ?? .current
      return LorvexPreviewClock.now(in: calendar)
    }

    /// `--ui-preview` seed: the fixed seed plus today-relative calendar events so
    /// the Today schedule agenda renders a realistic day, and optionally a day
    /// the assistant planned, with the rest of a busy day around it. The
    /// canonical import cannot represent the EventKit provider mirror, so the
    /// two events the fake marked `source: "provider"` seed as Lorvex-owned
    /// canonical events here.
    ///
    /// `plannedDay` seeds the assistant's briefing for today, more of the day's
    /// tasks (``seedTodayPool(_:)``), and, unless `untimed` is set, the times of
    /// two of them. `untimed` leaves the day without times, the state of anyone
    /// who never schedules. `dayState` then moves the seeded day into one of the
    /// states it never reaches by itself (``LorvexPreviewDayState``). `text`
    /// translates everything the seed writes as the user's or the assistant's
    /// words, so a run in another interface language shows sample content in it.
    public static func makeUIPreviewSeeded(
      todaySchedule: Bool, plannedDay: Bool = false, untimed: Bool = false,
      dayState: LorvexPreviewDayState? = nil, text: LorvexSampleText = .english
    ) async throws -> SwiftLorvexCoreService {
      let core = try await makeSeeded(wallClock: previewWallClock, text: text)
      if todaySchedule {
        for event in LorvexPreviewSeedData.todayPreviewEvents() {
          _ = try await core.importCalendarEvent(
            id: event.id, title: text(event.title), startDate: event.startDate,
            startTime: event.startTime, endDate: event.endDate, endTime: event.endTime,
            allDay: event.allDay, location: event.location.map { text($0) }, notes: nil, url: nil,
            color: event.color, eventType: event.eventType, personName: nil,
            attendees: nil, timezone: event.timezone, recurrence: nil,
            seriesId: nil, recurrenceInstanceDate: nil)
        }
      }
      if plannedDay {
        let (date, briefing, times) = LorvexPreviewSeedData.todayPreviewDay()
        // The briefing, the times, one deferral, and one memory note are the
        // assistant's work, so the changelog under Settings has assistant rows.
        try await SwiftLorvexCoreService.$currentInitiator.withValue(
          SwiftLorvexCoreService.ChangelogInitiator.assistant
        ) {
          _ = try await core.setDailyBriefingForMcp(date: date, briefing: text(briefing))
          if !untimed {
            _ = try await core.saveDayTimes(date: date, times: times)
          }
          if let tomorrow = LorvexDateFormatters.ymdUTCAddingDays(date, days: 1),
            let tomorrowDate = LorvexDateFormatters.ymdUTC.date(from: tomorrow)
          {
            _ = try await core.deferTask(
              id: LorvexPreviewSeedID.venueTask, until: tomorrowDate,
              reason: "blocked", note: text("The agenda comes first"))
          }
          _ = try await core.upsertMemory(
            key: "work_rhythm",
            content: text("Does deep work before lunch and keeps afternoons for meetings and email."))
        }
        try await seedTodayPool(core, text: text)
      }
      try seedAssistantSessions(core, now: previewWallClock())
      try await dayState?.apply(to: core, text: text)
      return core
    }

    /// More of the user's own tasks for today: one three days past its
    /// deadline, one due today, and one pushed to today three times, which is
    /// the count at which Today marks a task as pushed often.
    private static func seedTodayPool(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
      let anchor = logicalDayAnchor()
      _ = try await core.createTask(
        TaskCreateDraft(
          title: text("Renew the car registration"), priority: .p2, estimatedMinutes: 20,
          dueDate: day(anchor, daysAgo: 3), tags: text(["home"])))
      _ = try await core.createTask(
        TaskCreateDraft(
          title: text("Reply to Maya about the catering quote"), priority: .p2, estimatedMinutes: 15,
          dueDate: day(anchor, daysAgo: 0), tags: text(["work"])))
      let budget = try await core.createTask(
        TaskCreateDraft(
          title: text("Review the Q3 budget draft"), priority: .p3, estimatedMinutes: 45,
          tags: text(["work"])))
      guard let today = day(anchor, daysAgo: 0) else { return }
      for _ in 0..<3 {
        _ = try await core.deferTask(id: budget.id, until: today, reason: "not_today", note: nil)
      }
    }

    /// Records Claude Desktop as active the day before and Claude Code a few
    /// minutes ago, as the MCP helper would have, so Settings lists both.
    private static func seedAssistantSessions(_ core: SwiftLorvexCoreService, now: Date) throws {
      let sessions: [(name: String, title: String, version: String, minutesAgo: Int)] = [
        ("claude-ai", "Claude", "0.14.2", 26 * 60),
        ("claude-code", "Claude Code", "2.1.0", 4),
      ]
      try core.withLocalMaintenanceWrite { db in
        // Oldest first: each recording moves its client to the front.
        for session in sessions {
          try AssistantSessionsRepo.recordActivity(
            db, name: session.name, title: session.title, version: session.version,
            at: SyncTimestampFormat.formatSyncTimestamp(
              now.addingTimeInterval(TimeInterval(-60 * session.minutesAgo))))
        }
      }
    }

    /// Synchronous form of ``makeUIPreviewSeeded(todaySchedule:plannedDay:untimed:dayState:text:)``
    /// for launch-time construction (`--ui-preview` builds its `AppStore`
    /// inside the synchronous SwiftUI `App` init). Traps on a seed failure — a
    /// broken preview dataset is a build defect, not a runtime condition to
    /// recover from.
    public static func makeUIPreviewSeededBlocking(
      todaySchedule: Bool, plannedDay: Bool = false, untimed: Bool = false,
      dayState: LorvexPreviewDayState? = nil, text: LorvexSampleText = .english
    ) -> SwiftLorvexCoreService {
      waitForPreviewCore {
        try await makeUIPreviewSeeded(
          todaySchedule: todaySchedule, plannedDay: plannedDay, untimed: untimed,
          dayState: dayState, text: text)
      }
    }

    /// `--ui-preview -uiPreviewEmptyStore` core, built synchronously like
    /// ``makeUIPreviewSeededBlocking(todaySchedule:plannedDay:untimed:dayState:text:)``:
    /// the store of someone who has not added anything yet. It holds only
    /// what a new store holds (the schema's Inbox) plus the preview
    /// environment's preferences, whose timezone keeps the pinned preview
    /// clock and the product day in agreement.
    public static func makeUIPreviewEmptyBlocking() -> SwiftLorvexCoreService {
      waitForPreviewCore {
        let core = try SwiftLorvexCoreService.inMemory(wallClock: previewWallClock)
        try await SwiftLorvexCoreService.$currentInitiator.withValue(
          SwiftLorvexCoreService.ChangelogInitiator.importAttribution
        ) {
          try await seedPreferences(core)
        }
        return core
      }
    }

    /// Runs `make` on the concurrency pool and blocks the calling thread until
    /// it finishes. The service never hops to the main actor, so the wait
    /// cannot deadlock. Traps when `make` throws.
    private static func waitForPreviewCore(
      _ make: @escaping @Sendable () async throws -> SwiftLorvexCoreService
    ) -> SwiftLorvexCoreService {
      let box = ResultBox()
      let semaphore = DispatchSemaphore(value: 0)
      Task.detached {
        do {
          box.result = .success(try await make())
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

  private static func seed(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
    // The preview dataset is a synthetic bulk load, not a live user/assistant
    // session, so bind `import` provenance around the whole seed — the same
    // ambient the id-preserving importers inherit under `LorvexDataImporter`.
    // Without it the seed rows would inherit the `user` default and drop out of
    // the assistant-facing ai_changelog surface.
    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.importAttribution
    ) {
      try await seedPreferences(core)
      try await seedLists(core, text: text)
      try await seedTasks(core, text: text)
      try await seedHabits(core, text: text)
      try await seedCalendar(core, text: text)
      try await seedMemory(core, text: text)
      try await seedReview(core, text: text)
    }
  }

  /// The timezone the seed configures, and therefore the calendar its dates are
  /// anchored in. One constant so the stored preference and ``logicalDayAnchor()``
  /// cannot drift apart.
  private static let previewTimezone = "America/Los_Angeles"

  /// The preview environment's preferences. `setup_completed` is `"true"`:
  /// the dataset describes a store in active use, so previews render the
  /// workspaces rather than the setup wizard. (`default_list_id` is already
  /// schema-seeded to the sentinel Inbox.)
  private static let previewPreferences: [String: String] = [
    "working_hours": #"{"start":"09:00","end":"17:00"}"#,
    "timezone": "\"\(previewTimezone)\"",
    "theme": "\"system\"",
    "language": "\"en\"",
    "setup_completed": "true",
  ]

  private static func seedPreferences(_ core: SwiftLorvexCoreService) async throws {
    for (key, value) in previewPreferences.sorted(by: { $0.key < $1.key }) {
      _ = try await core.setPreference(key: key, value: value)
    }
  }

  private static func seedLists(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
    for list in LorvexPreviewSeedData.lists.lists {
      _ = try await core.importList(
        id: list.id, name: text(list.name), description: list.description.map { text($0) },
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
    LorvexPreviewSeedID.offsiteDatesTask: LorvexPreviewSeedID.appleNativeList,
  ]

  /// Day offsets, relative to the store's logical day, for the seeded tasks that
  /// belong to the day pool — chosen so the seed exercises every arm of it:
  /// `agendaTask` is ordinary work due today, `venueTask` is due today but
  /// blocked on `agendaTask`, and `statusUpdateTask` is overdue.
  /// `standingDeskTask` is absent on purpose: `someday` work is backlog, so a
  /// preview showing it under Today would be showing a bug.
  ///
  /// Deadlines rather than planned days: a `plannedDate` is also the surface
  /// stand-in for "deferred" (see ``Collection/lorvexDeferredSection``), so
  /// planning the seed would file it under Deferred and empty the Open section —
  /// a side effect of populating the day, not something the seed means to say.
  private static let taskDayOffsets: [LorvexTask.ID: Int] = [
    LorvexPreviewSeedID.agendaTask: 0,
    LorvexPreviewSeedID.venueTask: 0,
    LorvexPreviewSeedID.statusUpdateTask: 1,
  ]

  private static func seedTasks(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
    let dayAnchor = logicalDayAnchor()
    for task in LorvexPreviewSeedData.tasks {
      _ = try await core.importRemoteTask(
        id: task.id, title: text(task.title), notes: text(task.notes), aiNotes: nil,
        rawInput: nil, priority: task.priority, status: task.status,
        estimatedMinutes: task.estimatedMinutes,
        dueDate: taskDayOffsets[task.id].flatMap { day(dayAnchor, daysAgo: $0) },
        plannedDate: nil, availableFrom: nil,
        tags: text(task.tags), dependsOn: task.dependsOn)
      if let listID = taskListIDs[task.id] {
        _ = try await core.moveTask(id: task.id, toListID: listID)
      }
      // `importRemoteTask` carries `someday` and `completed` through directly
      // but not `cancelled`, so an abandoned seed row is replayed through the
      // real cancel mutation the way a move or a recurrence rule is.
      if task.status == .cancelled {
        _ = try await core.cancelTask(id: task.id)
      }
      for var item in task.checklistItems {
        item.text = text(item.text)
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

  /// How far back the seeded habits were created. A habit's 30-day adherence
  /// window opens on its creation day, so a habit stamped at seed time is
  /// scored over that single day and reports a flat 0% or 100% next to a streak
  /// counted from its seeded log. Creating them before their oldest completion
  /// makes the preview's rates the real trailing-30-day figures.
  private static let habitCreatedDaysAgo = 40

  private static func seedHabits(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
    let habitCreatedAt = SyncTimestampFormat.formatSyncTimestamp(
      Date().addingTimeInterval(TimeInterval(-habitCreatedDaysAgo) * 86_400))
    for (index, habit) in LorvexPreviewSeedData.habits.habits.enumerated() {
      _ = try await core.importHabit(
        id: habit.id, name: text(habit.name), icon: habit.icon, color: habit.color,
        cue: habit.cue.map { text($0) }, frequencyType: habit.frequencyType, weekdays: [],
        perPeriodTarget: nil, dayOfMonth: nil, targetCount: habit.targetCount,
        milestoneTarget: nil, archived: habit.archived, position: Int64(index),
        createdAt: habitCreatedAt)
      guard let counts = habitCompletionCounts[habit.id] else { continue }
      for _ in 0..<counts.today {
        _ = try await core.completeHabit(id: habit.id, date: ymd(daysAgo: 0))
      }
      for day in stride(from: 1, through: counts.priorDays, by: 1) {
        _ = try await core.completeHabit(id: habit.id, date: ymd(daysAgo: day))
      }
    }
  }

  private static func seedCalendar(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
    for event in LorvexPreviewSeedData.calendarEvents.events {
      _ = try await core.importCalendarEvent(
        id: event.id, title: text(event.title), startDate: event.startDate,
        startTime: event.startTime, endDate: event.endDate, endTime: event.endTime,
        allDay: event.allDay, location: event.location.map { text($0) }, notes: nil, url: nil,
        color: event.color, eventType: event.eventType, personName: nil,
        attendees: nil, timezone: event.timezone, recurrence: nil,
        seriesId: nil, recurrenceInstanceDate: nil)
    }
  }

  private static func seedMemory(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
    for entry in LorvexPreviewSeedData.memory.entries {
      _ = try await core.importMemoryEntry(
        key: entry.key, content: text(entry.content), updatedAt: entry.updatedAt)
    }
  }

  private static func seedReview(_ core: SwiftLorvexCoreService, text: LorvexSampleText) async throws {
    for review in LorvexPreviewSeedData.dailyReviews.values {
      _ = try await core.importDailyReview(
        date: review.date, summary: text(review.summary), mood: review.mood,
        energyLevel: review.energyLevel, wins: review.wins.map { text($0) },
        blockers: review.blockers.map { text($0) }, learnings: review.learnings.map { text($0) },
        timezone: review.timezone, updatedAt: review.updatedAt,
        linkedTaskIDs: review.linkedTaskIDs, linkedListIDs: review.linkedListIDs)
    }
  }

  private static func ymd(daysAgo: Int) -> String {
    LorvexDateFormatters.ymd.string(
      from: Date().addingTimeInterval(TimeInterval(-daysAgo) * 86_400))
  }

  /// `daysAgo` days before `anchor`, the UTC midnight of the seed's logical day.
  /// Day-granular writes re-format through `ymdUTC`, so the result round-trips to
  /// exactly the intended calendar day.
  private static func day(_ anchor: Date?, daysAgo: Int) -> Date? {
    anchor?.addingTimeInterval(TimeInterval(-daysAgo) * 86_400)
  }

  /// UTC midnight of the seed's logical day.
  ///
  /// Computed from ``previewTimezone`` — the zone this factory itself seeds — so
  /// it never queries the store: seeding runs for every preview and for hundreds
  /// of tests, and asking the database for its own logical day would add a write
  /// transaction to each one. Anchoring here rather than on a UTC-formatted
  /// `Date()` matters because planned and due dates are stored as UTC calendar
  /// days: a wall-clock anchor lands a day ahead every evening in this zone and
  /// would silently drop the whole seed out of the day pool.
  private static func logicalDayAnchor() -> Date? {
    let dayInPreviewZone = DateFormatter()
    dayInPreviewZone.calendar = Calendar(identifier: .gregorian)
    dayInPreviewZone.locale = Locale(identifier: "en_US_POSIX")
    dayInPreviewZone.dateFormat = "yyyy-MM-dd"
    dayInPreviewZone.timeZone = TimeZone(identifier: previewTimezone)
    return LorvexDateFormatters.ymdUTC.date(from: dayInPreviewZone.string(from: Date()))
  }
}
