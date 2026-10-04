#if DEBUG
  import Foundation

  /// Day arithmetic for the stress seed, so each seeding step states its dates
  /// as offsets from the store's logical today.
  private struct StressSeedDays {
    /// The store's logical today, `yyyy-MM-dd`.
    let today: String

    /// The `yyyy-MM-dd` key of the day `offset` days from today.
    func key(_ offset: Int) -> String {
      LorvexDateFormatters.ymdUTCAddingDays(today, days: offset) ?? today
    }

    /// UTC midnight of the day `offset` days from today, the instant a planned
    /// or due day is stored as, so it reads back as exactly that calendar day.
    func date(_ offset: Int) -> Date {
      LorvexDateFormatters.ymdUTC.date(from: key(offset)) ?? Date()
    }
  }

  /// Writes the stress content: the steps below, run in order against one core.
  private struct StressSeeder {
    let core: any LorvexCoreServicing
    let days: StressSeedDays
    /// The timezone calendar events are written in.
    let timezone: String

    func run() async {
      let launch = await seedStressLists()
      await seedStressTasks(launchList: launch)
      await seedStressCalendar()
      await seedStressHabits()
      await seedStressMemoryAndReviews()
    }

    /// Runs one seeding step, logging a failure instead of dropping it.
    private func stressSeed<T>(_ what: String, _ body: () async throws -> T) async -> T? {
      do {
        return try await body()
      } catch {
        NSLog("%@", "STRESS-SEED \(what) failed: \(error)")
        return nil
      }
    }

    private func seedStressLists() async -> LorvexList? {
      let launch = await stressSeed("launch list") {
        try await core.createList(
          name:
            "Cross-functional launch readiness with legal, security, support and regional marketing",
          description:
            "Everything that must be true before the launch date is confirmed: sign-offs, "
            + "localized collateral, support macros, and the rollback plan the on-call rotation "
            + "agreed to.",
          color: "#FF375F", icon: "paperplane.fill")
      }
      let extras: [(String, String, String)] = [
        ("Errands", "cart.fill", "#FF9500"), ("Finance", "creditcard.fill", "#30B0C7"),
        ("Health", "heart.fill", "#FF2D55"), ("Travel", "airplane", "#5AC8FA"),
        ("Home projects", "hammer.fill", "#A2845E"), ("Side project", "lightbulb.fill", "#FFCC00"),
        ("Learning", "graduationcap.fill", "#5856D6"), ("Gifts", "gift.fill", "#FF6482"),
        ("Garden", "leaf.fill", "#32D74B"), ("Car", "car.fill", "#8E8E93"),
      ]
      for (name, icon, color) in extras {
        _ = await stressSeed("list \(name)") {
          try await core.createList(name: name, description: nil, color: color, icon: icon)
        }
      }
      return launch
    }

    private func seedStressTasks(launchList: LorvexList?) async {
      let manyTags = [
        "work", "urgent", "engineering", "research", "home", "errands", "q4-planning", "finance",
        "a-remarkably-long-tag-name-that-has-to-truncate-somewhere", "health",
      ]
      let notes = """
        ## Launch checklist

        The rollout happens in **three waves** (internal, beta, everyone). Each wave needs the \
        previous one to be quiet for 24 hours.

        - Confirm the feature flags are off by default
        - Walk the on-call rotation through the rollback plan, including the database restore \
        from the *previous night's* snapshot
        - Post the status page template in the support channel

        1. Internal wave on Tuesday
        2. Beta wave on Thursday
        3. Everyone the following Monday

        > If the error budget is below 40% at any gate, stop and call the incident commander.

        Reference: https://example.com/runbooks/launch-readiness/rollback-and-restore-procedures-for-the-sync-service-v2

        `rollout --wave=beta --percent=25 --dry-run`
        """

      let drafts: [TaskCreateDraft] = [
        .init(
          title:
            "Prepare the quarterly business review deck for the leadership offsite, including the "
            + "revenue forecast, the hiring plan, the infrastructure cost review, and the customer "
            + "escalation summary",
          listID: launchList?.id, priority: .p1, estimatedMinutes: 180, dueDate: days.date(0),
          plannedDate: days.date(0), tags: manyTags),
        .init(
          title: "Renew the vehicle registration before the penalty period starts", priority: .p1,
          dueDate: days.date(-45)),
        .init(
          title: "Chase the invoice that was due three weeks ago", priority: .p2,
          dueDate: days.date(-21), plannedDate: days.date(-21)),
        .init(
          title:
            "https://example.com/documents/quarterly-review/2026/q4/forecast-assumptions-and-sensitivity-analysis-final-v7-reviewed.pdf",
          priority: .p2, estimatedMinutes: 15, plannedDate: days.date(0)),
        .init(
          title: "🚀 Ship the 新版本 release — مراجعة الإصدار שלום 🎉", priority: .p3,
          plannedDate: days.date(0), tags: ["日本語", "العربية"]),
        .init(title: "x", priority: .p2, dueDate: days.date(1), tags: ["a"]),
        .init(title: "Reply to Sam", priority: .p3, estimatedMinutes: 5, plannedDate: days.date(0)),
        .init(
          title: "Facilitate the full-day planning workshop for the platform and growth teams",
          priority: .p2, estimatedMinutes: 480, plannedDate: days.date(0)),
        .init(
          title: "Renew the domain registration and the wildcard certificate", priority: .p3,
          dueDate: days.date(400)),
        .init(
          title: "Pay the quarterly estimated taxes and file the supporting worksheet",
          priority: .p2, dueDate: days.date(10),
          recurrence: TaskRecurrenceRule(freq: .monthly, interval: 3)),
        .init(
          title: "Overlap A: draft the announcement", priority: .p2, estimatedMinutes: 60,
          plannedDate: days.date(1), plannedTime: (13 * 60)..<(14 * 60)),
        .init(
          title: "Overlap B: review the legal copy with the counsel", priority: .p2,
          estimatedMinutes: 60, plannedDate: days.date(1), plannedTime: (13 * 60 + 30)..<(14 * 60 + 30)),
        .init(
          title: "Overlap C", priority: .p3, estimatedMinutes: 30, plannedDate: days.date(1),
          plannedTime: (13 * 60 + 45)..<(14 * 60 + 15)),
      ]
      for draft in drafts {
        _ = await stressSeed("task \(draft.title.prefix(24))") { try await core.createTask(draft) }
      }

      await seedStressChecklistTask(launchList: launchList, notes: notes)
      await seedStressDependentTask(launchList: launchList)
      await seedStressFillerTasks()
    }

    /// A task with long markdown notes and a 25-row checklist, nine rows done.
    private func seedStressChecklistTask(launchList: LorvexList?, notes: String) async {
      guard
        let task = await stressSeed("checklist task", {
          try await core.createTask(
            .init(
              title: "Write the launch checklist and walk the on-call rotation through it",
              notes: notes, listID: launchList?.id, priority: .p1, estimatedMinutes: 90,
              dueDate: days.date(2), plannedDate: days.date(0), tags: ["work", "launch"]))
        })
      else { return }
      let items = [
        "Confirm the feature flags are off by default",
        "Walk the on-call rotation through the rollback plan, including the database restore from "
          + "the previous night's snapshot and the order in which the regional replicas come back",
        "Post the status page template in the support channel", "Legal", "QA", "Security",
        "Draft the customer email", "Translate the release notes", "Schedule the social posts",
        "Brief the sales team on the pricing change", "Update the help center", "Record the demo",
        "Confirm the on-call schedule for launch week and the weekend after it",
        "Check the dashboards", "Freeze the main branch", "Tag the release candidate",
        "Run the full regression suite on the three oldest supported devices",
        "Notify the partners", "Archive the old assets", "Back up the production database",
        "Rehearse the rollback", "Send the launch-day agenda", "Book the retro",
        "Thank the team", "Close the launch epic",
      ]
      var latest = task
      for item in items {
        if let updated = await stressSeed("checklist item", {
          try await core.addTaskChecklistItem(taskID: task.id, text: item)
        }) {
          latest = updated
        }
      }
      for item in latest.checklistItems.prefix(9) {
        _ = await stressSeed("checklist toggle", {
          try await core.toggleTaskChecklistItem(itemID: item.id, completed: true)
        })
      }
    }

    /// A task that waits on three others, one with a long title.
    private func seedStressDependentTask(launchList: LorvexList?) async {
      var blockers: [LorvexTask.ID] = []
      for title in [
        "Legal sign-off on the launch terms",
        "Security review of the new sync endpoint",
        "Support macros translated into all fifteen supported languages before the launch date",
      ] {
        if let blocker = await stressSeed("blocker", {
          try await core.createTask(
            .init(title: title, listID: launchList?.id, priority: .p2, dueDate: days.date(3)))
        }) {
          blockers.append(blocker.id)
        }
      }
      _ = await stressSeed("dependent task") {
        try await core.createTask(
          .init(
            title: "Announce the launch", listID: launchList?.id, priority: .p2,
            dueDate: days.date(5), dependsOn: blockers))
      }
    }

    /// Thirty ordinary tasks that lengthen every list and spread across the
    /// coming days, plus a few completed and a few parked as Someday.
    private func seedStressFillerTasks() async {
      let topics = [
        "vendor invoice", "design handoff", "release notes", "travel receipts", "onboarding doc",
        "security patch", "customer survey", "budget review", "interview feedback",
        "contract renewal",
      ]
      let priorities: [LorvexTask.Priority] = [.p1, .p2, .p3]
      for index in 0..<30 {
        let topic = topics[index % topics.count]
        var draft = TaskCreateDraft(
          title: "Follow up on the \(topic) (\(index + 1))", priority: priorities[index % 3],
          dueDate: days.date(index % 9 - 3), tags: [topic.split(separator: " ")[0].lowercased()])
        if index % 3 == 0 {
          draft.plannedDate = days.date(index % 4)
          draft.estimatedMinutes = 30
        }
        _ = await stressSeed("filler \(index)") { try await core.createTask(draft) }
      }
      for index in 1...5 {
        if let done = await stressSeed("done task", {
          try await core.createTask(
            .init(
              title:
                "Wrap up the \(topics[index]) and send the summary to everyone who attended",
              priority: .p3))
        }) {
          _ = await stressSeed("complete", { try await core.completeTask(id: done.id) })
        }
      }
      for title in [
        "Learn to sail", "Write the book", "Plan the trip across the whole of South America",
      ] {
        if let someday = await stressSeed("someday task", {
          try await core.createTask(.init(title: title, priority: .p3))
        }) {
          _ = await stressSeed("park", { try await core.markTaskSomeday(id: someday.id) })
        }
      }
    }

    private func seedStressCalendar() async {
      func event(
        _ title: String, _ offset: Int, _ start: String?, _ end: String?, endOffset: Int? = nil,
        location: String? = nil, notes: String? = nil
      ) async {
        _ = await stressSeed("event \(title.prefix(24))") {
          try await core.createCalendarEvent(
            title: title, startDate: days.key(offset), endDate: endOffset.map(days.key),
            startTime: start, endTime: end, allDay: start == nil, location: location,
            notes: notes, recurrence: nil, timezone: timezone, url: nil,
            color: nil, eventType: nil, personName: nil, attendees: nil)
        }
      }

      // Today: a three-way overlap with a long title and a short event, one
      // event with a location and notes, and an overnight event.
      await event(
        "Quarterly planning workshop", 0, "10:00", "11:30",
        location: "Large conference room on the fourth floor, east wing",
        notes: "Bring the revenue forecast and the hiring plan. Lunch is provided.")
      await event(
        "Customer escalation sync with the enterprise support leads and the account team", 0,
        "10:30", "12:00")
      await event("Quick sync", 0, "11:00", "11:15")
      await event("Release night watch", 0, "22:00", "02:00", endOffset: 1)

      // Tomorrow: three all-day events beside five timed ones.
      await event("Company holiday", 1, nil, nil)
      await event("Priya's birthday", 1, nil, nil)
      await event("Conference travel day", 1, nil, nil)
      for (title, start, end) in [
        ("Airport transfer", "06:30", "07:15"), ("Flight to the summit", "08:30", "11:45"),
        ("Hotel check-in", "13:00", "13:30"), ("Speaker briefing", "15:00", "16:00"),
        ("Welcome dinner", "19:00", "21:30"),
      ] {
        await event(title, 1, start, end)
      }

      // A five-day conference, a 15-day freeze window, and mixed-script text.
      await event("Annual engineering summit and partner conference", 2, nil, nil, endOffset: 6)
      await event("Platform migration freeze window", -2, nil, nil, endOffset: 12)
      await event("🎂 عيد ميلاد سارة", 5, nil, nil)

      // A crowded day, for the month grid's overflow count.
      for (title, start, end) in [
        ("Breakfast with Priya", "08:00", "08:45"), ("Standup", "09:00", "09:15"),
        ("Code review", "09:30", "10:30"), ("Lunch and learn", "12:00", "13:00"),
        ("Vendor demo", "13:30", "14:00"), ("Budget check-in", "14:00", "14:30"),
        ("Coffee chat", "15:00", "15:30"), ("Retro", "16:00", "17:00"),
        ("Dinner with parents", "19:00", "21:00"),
      ] {
        await event(title, 3, start, end)
      }

      // Events far from today, for month navigation.
      await event("Offsite planning", -10, "10:00", "11:00")
      await event("Quarterly board meeting", 25, "09:00", "12:00")
    }

    private func seedStressHabits() async {
      let habits: [(String, String?, String, String, HabitCadenceInput)] = [
        (
          "Practice the piano scales and arpeggios for at least twenty minutes",
          "After the evening walk, once the dishes are done and the kitchen is quiet again",
          "pianokeys", "#FF2D55", .daily
        ),
        (
          "Strength training", "Before work", "dumbbell.fill", "#FF9500",
          HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2, 4])
        ),
        (
          "Swim laps", nil, "figure.pool.swim", "#30B0C7",
          HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3)
        ),
        (
          "Pay the credit card", "Mid-month", "creditcard.fill", "#34C759",
          HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 15)
        ),
        ("Stretch", "After the shower", "figure.flexibility", "#5E5CE6", .daily),
        ("Water the plants", nil, "leaf.fill", "#32D74B", .daily),
        ("Floss", nil, "sparkles", "#5AC8FA", .daily),
        ("Vitamins", "With breakfast", "pills.fill", "#FFCC00", .daily),
        ("Drink two liters of water", nil, "drop.fill", "#0A84FF", .daily),
        ("Lights out by eleven", "Phone on the charger across the room", "moon.stars.fill", "#AF52DE", .daily),
      ]
      for (index, spec) in habits.enumerated() {
        let (name, cue, icon, color, cadence) = spec
        guard
          let habit = await stressSeed("habit \(name.prefix(24))", {
            try await core.createHabit(
              name: name, cue: cue, icon: icon, color: color, targetCount: 1, cadence: cadence,
              milestoneTarget: nil)
          })
        else { continue }
        // A broken streak on the first habit; recent runs on the daily others.
        let offsets: [Int] =
          index == 0 ? [0, 1, 2, 3, 4, 7, 8, 9, 10, 11, 12, 13] : (cadence == .daily ? Array(0..<(index % 5 + 1)) : [])
        for offset in offsets {
          _ = await stressSeed("habit completion") {
            try await core.completeHabit(id: habit.id, date: days.key(-offset))
          }
        }
      }
    }

    private func seedStressMemoryAndReviews() async {
      let memories: [(String, String)] = [
        (
          "a_remarkably_long_memory_key_that_describes_a_preference_in_great_detail",
          "Prefers the quiet car on trains, an aisle seat on flights, and a hotel that is within "
            + "ten minutes of the venue on foot, because the commute is the part of travel that "
            + "wears them out the most.\n\nBooks flights through the travel desk, never directly, "
            + "and wants the itinerary as a single message the evening before.\n\nDoes not take "
            + "calls before 9am local time unless the assistant has flagged them as urgent."
        ),
        ("emoji_and_scripts", "🚀 Ship it — مرحبا שלום 你好 नमस्ते こんにちは"),
        ("short", "Yes."),
      ]
      for (key, content) in memories {
        _ = await stressSeed("memory \(key.prefix(16))") {
          try await core.upsertMemory(key: key, content: content)
        }
      }
      _ = await stressSeed("long review") {
        try await core.upsertDailyReviewPreservingLinks(
          date: days.key(-4),
          summary:
            "A day that started well and then split into three directions at once: the incident "
            + "call ran for two hours, the planning review slipped to the afternoon, and the "
            + "investor update only went out after dinner. Nothing was dropped, but nothing was "
            + "finished early either.",
          mood: 2, energyLevel: 2,
          wins:
            "Shipped the sync fix, cleared the support backlog, and finally answered the thread "
            + "from the partner team that had been waiting since Monday.",
          blockers:
            "Waiting on legal for the launch terms, on design for the calendar grid, and on the "
            + "platform team for the staging environment, which has been down since Tuesday.",
          learnings:
            "Put the hardest task before the first meeting, not after it, and decline the "
            + "recurring call that has not had an agenda in a month.")
      }
    }
  }

  /// Dev/QA only: content that breaks layouts, for capture runs. Adding it on top
  /// of the sample day lets a capture show how each screen copes with titles
  /// that wrap across many lines or never break, many and very long tags, a
  /// very long list name, long notes with a large checklist, tasks overdue by
  /// weeks and due a year out, a day booked past its capacity with
  /// overlapping plan blocks, overlapping, all-day, multi-day and overnight
  /// events, a crowded day, and long habit and memory text.
  public enum LorvexStressSeed {
    /// The launch argument that asks for the stress content, passed beside the
    /// sample-data or preview seed it is added to.
    public static let launchArgument = "-lorvexSeedStressData"

    /// Whether this launch asked for the stress content.
    public static var isRequested: Bool { CommandLine.arguments.contains(launchArgument) }

    /// The tasks the macOS tour opens in the inspector, each as the tour stop
    /// that captures it and the start of the task's title: the task with ten
    /// tags and a title of five lines, the task with a 25-item checklist and
    /// long notes, and the task that waits on three others.
    public static let inspectorTasks: [(stop: String, titlePrefix: String)] = [
      ("tasks-inspector-tags", "Prepare the quarterly business review deck"),
      ("tasks-inspector-checklist", "Write the launch checklist"),
      ("tasks-inspector-dependencies", "Announce the launch"),
    ]

    /// The start of the very long list name, the list the tour's list stops
    /// show in place of the first list.
    public static let longListNamePrefix = "Cross-functional launch readiness"

    /// The start of the long habit name the tour opens in the habit inspector.
    public static let longHabitNamePrefix = "Practice the piano scales"

    /// Writes the stress content through `core`, with every date an offset from
    /// `today` (the store's logical day, `yyyy-MM-dd`) and calendar events in
    /// `timezone`. Task reminders are never seeded, because their permission
    /// alert covers captures. A step the core rejects is logged as
    /// `STRESS-SEED … failed` and skipped.
    public static func apply(
      to core: any LorvexCoreServicing, today: String, timezone: String
    ) async {
      await StressSeeder(core: core, days: StressSeedDays(today: today), timezone: timezone).run()
    }
  }
#endif
