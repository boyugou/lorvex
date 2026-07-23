import Foundation

/// Stable ids for the fixed preview dataset. Canonical hyphenated lowercase
/// UUID literals because the real store's sync outbox validates every entity
/// id it enqueues; tests and previews reference rows through these names
/// rather than raw UUID strings.
public enum LorvexPreviewSeedID {
  /// The schema's sentinel Inbox list id: `schema.sql` seeds the row and task
  /// `list_id` defaults to it, so the preview seed reuses it rather than
  /// importing a second inbox.
  public static let inboxList = "inbox"
  public static let appleNativeList = "ec31eb74-d473-4d6a-9145-ca7a3e05568c"
  /// "Draft the team offsite agenda" (P1, open, in `appleNativeList`).
  public static let agendaTask = "4fd40c50-bcbc-4cdb-aa3a-b8daeac1d8e0"
  /// "Book the offsite venue" (P1, open, in `inboxList`, depends on `agendaTask`).
  public static let venueTask = "704d0712-7a81-4c4b-9db3-c3d5f11ca42d"
  /// "Send the weekly status update" (P2, open, in `appleNativeList`, weekly recurrence).
  public static let statusUpdateTask = "6cf6e6c4-f5bc-430a-bab9-4d616c203ee3"
  /// "Look into a standing-desk setup" (P3, someday, no list).
  public static let standingDeskTask = "7de3b319-7952-4cef-a088-f99c3c60f686"
  public static let agendaChecklistConfirm = "0a27bc0f-caf0-497b-af7a-f8ca7524b776"
  public static let agendaChecklistShare = "d89d33d4-eccd-4b50-9496-85265da9dd89"
  public static let venueReminder = "023fa9c1-afa7-45a7-b681-2172d4182d5c"
  /// "Daily Review" (daily, target 1, completed once today).
  public static let dailyReviewHabit = "fd707b37-023e-4a40-a378-58c8bdd85a3c"
  /// "Evening walk" (daily, target 1, not completed today).
  public static let eveningWalkHabit = "43fa7366-cc35-4549-a8e5-7a845a1db6cf"
  /// "Swift migration review" calendar event on 2026-05-22.
  public static let migrationReviewEvent = "a398eef6-9efc-4631-bf86-550e7ad32e31"
  public static let previewStandupEvent = "16c1f029-e296-4f3a-9519-ea2448b27836"
  public static let previewOneOnOneEvent = "45d8fa73-2904-4f75-82fd-6f38435556b5"
  public static let previewDesignEvent = "701ec600-9189-4a47-9895-0d04752e38a6"
}

enum LorvexPreviewSeedData {
  static let memory = MemorySnapshot(entries: [
    MemoryEntry(
      key: "notes_for_ai",
      content: "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.",
      updatedAt: "2026-05-22T00:00:00Z"
    ),
    MemoryEntry(
      key: "swift_migration",
      content:
        "Before switching laptops, export the database and photo library so nothing is lost in the move.",
      updatedAt: "2026-05-22T00:00:00Z"
    ),
  ])

  static let dailyReviews: [String: DailyReviewEntry] = [
    "2026-05-22": DailyReviewEntry(
      date: "2026-05-22",
      summary:
        "Reviewed the week and lined up next week's offsite planning.",
      mood: 4,
      energyLevel: 3,
      wins: "Cleared the inbox and locked in the offsite dates.",
      blockers: "Still waiting on venue quotes before booking.",
      learnings: "Batching errands into one afternoon freed up the rest of the week.",
      timezone: "America/Los_Angeles",
      updatedAt: "2026-05-22T00:00:00Z",
      linkedTaskIDs: [LorvexPreviewSeedID.agendaTask],
      linkedListIDs: [LorvexPreviewSeedID.appleNativeList]
    )
  ]

  // The Inbox is not part of the seed: `schema.sql` seeds the sentinel row
  // (`id = 'inbox'`) itself, and imported tasks land there by default.
  static let lists = ListCatalogSnapshot(lists: [
    LorvexList(
      id: LorvexPreviewSeedID.appleNativeList,
      name: "Apple Native",
      color: "#0A84FF",
      icon: "macwindow",
      description: "Apple ecosystem apps and gear to try",
      openCount: 2,
      totalCount: 2,
      updatedAt: "2026-05-22T00:00:00Z"
    )
  ])

  static let habits = HabitCatalogSnapshot(habits: [
    LorvexHabit(
      id: LorvexPreviewSeedID.dailyReviewHabit,
      name: "Daily Review",
      icon: "checkmark.seal",
      color: "#34C759",
      cue: "End of day",
      frequencyType: "daily",
      targetCount: 1,
      completionsToday: 1,
      totalCompletions: 12,
      completionRate30d: 0.4,
      archived: false
    ),
    LorvexHabit(
      id: LorvexPreviewSeedID.eveningWalkHabit,
      name: "Evening walk",
      icon: "figure.walk",
      color: "#007AFF",
      cue: "After dinner",
      frequencyType: "daily",
      targetCount: 1,
      completionsToday: 0,
      totalCompletions: 8,
      completionRate30d: 0.27,
      archived: false
    ),
  ])

  static let calendarEvents = CalendarTimelineSnapshot(
    from: "2026-05-22",
    to: "2026-05-29",
    events: [
      CalendarTimelineEvent(
        id: LorvexPreviewSeedID.migrationReviewEvent,
        title: "Swift migration review",
        source: "canonical",
        editable: true,
        startDate: "2026-05-22",
        startTime: "15:00",
        endDate: nil,
        endTime: "15:45",
        allDay: false,
        location: "Conference Room B",
        color: "#007AFF",
        eventType: "event",
        timezone: "America/Los_Angeles",
        isRecurring: false
      )
    ],
    truncated: false,
    nextOffset: nil
  )

  #if DEBUG
    /// Today-relative calendar events for `--ui-preview` so the Today schedule
    /// agenda populates with a realistic day. Two are `source: "provider"` to
    /// stand in for mirrored EventKit external-calendar events (the common
    /// real-world case), one is a Lorvex-owned canonical event. Computed from the
    /// current date, so it is preview-only — the fixed-date seed above stays the
    /// deterministic source for tests.
    static func previewTodayString() -> String {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter.string(from: Date())
    }

    static func todayPreviewEvents() -> [CalendarTimelineEvent] {
      let today = previewTodayString()
      let zone = TimeZone.current.identifier
      return [
        CalendarTimelineEvent(
          id: LorvexPreviewSeedID.previewStandupEvent, title: "Team standup", source: "provider", editable: false,
          startDate: today, startTime: "09:30", endDate: nil, endTime: "09:45", allDay: false,
          location: "Zoom", color: nil, eventType: "event", timezone: zone, isRecurring: true),
        CalendarTimelineEvent(
          id: LorvexPreviewSeedID.previewOneOnOneEvent, title: "1:1 with Sam", source: "provider", editable: false,
          startDate: today, startTime: "13:00", endDate: nil, endTime: "13:30", allDay: false,
          location: nil, color: nil, eventType: "event", timezone: zone, isRecurring: false),
        CalendarTimelineEvent(
          id: LorvexPreviewSeedID.previewDesignEvent, title: "Design review", source: "canonical", editable: true,
          startDate: today, startTime: "15:30", endDate: nil, endTime: "16:30", allDay: false,
          location: "Studio", color: "#007AFF", eventType: "event", timezone: zone, isRecurring: false),
      ]
    }

    /// A saved focus plan + schedule for today that interleaves the today
    /// preview events (`event` blocks) with deep-work `task` blocks and a
    /// `buffer`, so `--ui-preview -uiPreviewFocusSchedule` renders the unified
    /// mixed timeline (and exercises all three block-kind labels).
    static func todayPreviewFocus() -> (CurrentFocusPlan, FocusSchedule) {
      let today = previewTodayString()
      let zone = TimeZone.current.identifier
      let plan = CurrentFocusPlan(
        date: today,
        taskIDs: [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.statusUpdateTask],
        briefing: "Two deep-work blocks fitted around today's meetings.",
        timezone: zone,
        localChangeSequence: 0)
      let blocks: [FocusScheduleBlock] = [
        FocusScheduleBlock(
          blockType: "event", startTime: "09:30", endTime: "09:45",
          calendarEventID: LorvexPreviewSeedID.previewStandupEvent, eventSource: .canonical,
          title: "Team standup"),
        FocusScheduleBlock(
          blockType: "task", startTime: "09:45", endTime: "10:45",
          taskID: LorvexPreviewSeedID.agendaTask, title: "Draft the team offsite agenda"),
        FocusScheduleBlock(blockType: "buffer", startTime: "10:45", endTime: "10:55"),
        FocusScheduleBlock(
          blockType: "task", startTime: "10:55", endTime: "11:55",
          taskID: LorvexPreviewSeedID.statusUpdateTask, title: "Send the weekly status update"),
        FocusScheduleBlock(
          blockType: "event", startTime: "13:00", endTime: "13:30",
          calendarEventID: LorvexPreviewSeedID.previewOneOnOneEvent, eventSource: .canonical,
          title: "1:1 with Sam"),
        FocusScheduleBlock(
          blockType: "event", startTime: "15:30", endTime: "16:30",
          calendarEventID: LorvexPreviewSeedID.previewDesignEvent, eventSource: .canonical,
          title: "Design review"),
      ]
      let schedule = FocusSchedule(
        date: today,
        rationale: "Deep work fitted around your meetings.",
        timezone: zone,
        workingHours: FocusScheduleWorkingHours(start: "09:00", end: "17:00"),
        totalMinutesAvailable: 360,
        calendarEventsCount: 3,
        blocks: blocks)
      return (plan, schedule)
    }
  #endif

  static let tasks: [LorvexTask] = [
    LorvexTask(
      id: LorvexPreviewSeedID.agendaTask,
      title: "Draft the team offsite agenda",
      notes: "Block out sessions, pick a keynote, and leave time for breakouts.",
      priority: .p1,
      status: .open,
      dueDate: nil,
      estimatedMinutes: 90,
      tags: ["work", "planning"],
      checklistItems: [
        TaskChecklistItem(
          id: LorvexPreviewSeedID.agendaChecklistConfirm, taskID: LorvexPreviewSeedID.agendaTask, position: 0,
          text: "Confirm session topics with the leads",
          completedAt: "2026-05-22T10:00:00Z"
        ),
        TaskChecklistItem(
          id: LorvexPreviewSeedID.agendaChecklistShare, taskID: LorvexPreviewSeedID.agendaTask, position: 1,
          text: "Share the draft agenda for feedback",
          completedAt: nil
        ),
      ]
    ),
    LorvexTask(
      id: LorvexPreviewSeedID.venueTask,
      title: "Book the offsite venue",
      notes: "Compare the two shortlisted venues and reserve the one that fits the group.",
      priority: .p1,
      status: .open,
      dueDate: nil,
      estimatedMinutes: 60,
      tags: ["work"],
      dependsOn: [LorvexPreviewSeedID.agendaTask],
      reminders: [
        TaskReminder(id: LorvexPreviewSeedID.venueReminder, reminderAt: "2099-12-31T09:00:00Z", status: "pending")
      ]
    ),
    LorvexTask(
      id: LorvexPreviewSeedID.statusUpdateTask,
      title: "Send the weekly status update",
      notes: "Summarize progress, blockers, and next steps for the team.",
      priority: .p2,
      status: .open,
      dueDate: nil,
      estimatedMinutes: 120,
      tags: ["work", "weekly"],
      recurrence: TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO"])
    ),
    LorvexTask(
      id: LorvexPreviewSeedID.standingDeskTask,
      title: "Look into a standing-desk setup",
      notes: "Keep this as a someday idea until the home office is sorted.",
      priority: .p3,
      status: .someday,
      dueDate: nil,
      estimatedMinutes: nil,
      tags: ["home"]
    ),
  ]
}
