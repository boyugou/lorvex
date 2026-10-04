#if DEBUG
  import Foundation
  import LorvexCore
  import SwiftUI

  /// Dev/QA only: the `lorvex://firsttask/compose/<checklist|reminder>` screenshot
  /// hook parks which inline composer the task detail should unfold on its next
  /// appearance, and `lorvex://firsttask/field/<field>` (or
  /// `lorvex://findtask/<title>/field/<field>`) which field's editor it should
  /// raise (a ``MobileTaskField`` raw value). The
  /// detail consumes each value once, so later pushes of a task detail in the
  /// same process start folded again.
  enum MobileTaskDetailDebugState {
    enum Composer: String {
      case checklist
      case reminder
    }

    @MainActor static var initialComposer: Composer?
    @MainActor static var initialField: MobileTaskField?

    @MainActor static func takeInitialComposer() -> Composer? {
      defer { initialComposer = nil }
      return initialComposer
    }

    @MainActor static func takeInitialField() -> MobileTaskField? {
      defer { initialField = nil }
      return initialField
    }
  }

  /// Dev/QA only: the `lorvex://sheet/event` screenshot hook parks the draft the
  /// calendar opens its New Event sheet on at its next appearance. Consumed
  /// once, so later visits start with the sheet closed.
  enum MobileCalendarDebugState {
    @MainActor static var initialCreateDraft: MobileCalendarDraft?

    @MainActor static func takeInitialCreateDraft() -> MobileCalendarDraft? {
      defer { initialCreateDraft = nil }
      return initialCreateDraft
    }
  }

  /// Dev/QA only: the `lorvex://memorycomposer` screenshot hook asks the Memory
  /// workspace to raise its New Memory sheet on its next appearance. Consumed
  /// once, so later visits start with the sheet closed.
  enum MobileMemoryDebugState {
    @MainActor static var presentsComposerOnAppear = false

    @MainActor static func takePresentsComposerOnAppear() -> Bool {
      defer { presentsComposerOnAppear = false }
      return presentsComposerOnAppear
    }
  }

  /// Dev/QA only: the `lorvex://tab/<name>/search/<query>` screenshot hook
  /// pre-fills the search field of that workspace, so its no-results row can
  /// be captured without typing. The query is keyed by workspace because one
  /// workspace can sit on another's stack: the Habits workspace is pushed over
  /// the Tasks home, which appears first and must not take the query meant for
  /// Habits. Consumed once.
  enum MobileSearchDebugState {
    @MainActor static var initialQuery: (workspace: MobileDestination, query: String)?

    @MainActor static func takeInitialQuery(for workspace: MobileDestination) -> String? {
      guard let initialQuery, initialQuery.workspace == workspace else { return nil }
      Self.initialQuery = nil
      return initialQuery.query
    }
  }

  /// The mode the Review tab opens in when a screenshot run asks for the week
  /// digest (`lorvex://tab/review/week`); the Review view consumes it once.
  enum MobileReviewDebugState {
    @MainActor static var initialMode: MobileReviewMode?

    @MainActor static func takeInitialMode() -> MobileReviewMode? {
      defer { initialMode = nil }
      return initialMode
    }
  }

  extension MobileStore {
    /// Dev/QA only: seed a realistic sample dataset so populated layouts can be
    /// inspected in the simulator during the UI redesign. Triggered by the
    /// `-lorvexSeedSampleData` launch argument and no-ops unless the store is
    /// empty, so relaunching never duplicates. Compiled out of release builds.
    /// Writes through the normal core path (valid HLC / changelog), never a
    /// preview/in-memory backend. The content is written in the language the
    /// interface runs in (``LorvexSampleText``), so a capture run launched with
    /// `-AppleLanguages (zh-Hans)` shows Chinese tasks under a Chinese interface.
    public func debugSeedSampleDataIfNeeded() async {
      guard CommandLine.arguments.contains("-lorvexSeedSampleData") else { return }
      guard
        let existing = try? await core.listTasks(
          status: "all", listID: nil, priority: nil, text: nil, limit: 1, offset: 0),
        existing.tasks.isEmpty
      else { return }
      let text = LorvexSampleText(language: .running)

      let calendar = Calendar.current
      func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
      }
      let ymd = DateFormatter()
      ymd.dateFormat = "yyyy-MM-dd"
      ymd.locale = Locale(identifier: "en_US_POSIX")
      let todayYMD = ymd.string(from: Date())

      // A few lists with distinct icons + colors so catalog tiles show variety.
      let work = try? await core.createList(
        name: text("Work"), description: text("Day job & deep work"), color: "#0A84FF",
        icon: "briefcase.fill")
      let personal = try? await core.createList(
        name: text("Personal"), description: nil, color: "#34C759", icon: "house.fill")
      _ = try? await core.createList(
        name: text("Reading"), description: text("Papers & books"), color: "#AF52DE",
        icon: "book.fill")

      let drafts: [TaskCreateDraft] = [
        .init(
          title: text("Reply to the investor update email"), priority: .p1,
          dueDate: day(-1), plannedDate: day(-1), tags: text(["work", "urgent"])),
        .init(
          title: text("Review the Q3 planning doc"), listID: work?.id, priority: .p1,
          estimatedMinutes: 45, dueDate: day(0), plannedDate: day(0), tags: text(["work"])),
        .init(
          title: text("Refactor the sync layer"), listID: work?.id, priority: .p2,
          estimatedMinutes: 90, plannedDate: day(0), tags: text(["engineering"])),
        .init(
          title: text("Buy groceries for the week"), listID: personal?.id, priority: .p2,
          plannedDate: day(0), tags: text(["home"])),
        .init(title: text("Read the GRPO paper"), priority: .p2, tags: text(["research"])),
        .init(title: text("Renew passport"), priority: .p3, dueDate: day(5)),
        .init(title: text("Plan the spring offsite"), priority: .p3, tags: text(["someday"])),
      ]
      var created: [LorvexTask] = []
      for draft in drafts {
        if let task = try? await core.createTask(draft) { created.append(task) }
      }
      // Write the day's briefing, give two of today's tasks times, and defer
      // one task, all as the assistant, so the changelog under Settings has
      // assistant rows and the schedule and the calendar have timed tasks to
      // draw.
      if created.count >= 4 {
        await SwiftLorvexCoreService.$currentInitiator.withValue(
          SwiftLorvexCoreService.ChangelogInitiator.assistant
        ) {
          _ = try? await (core as? any LorvexMcpMutationServicing)?.setDailyBriefingForMcp(
            date: todayYMD,
            briefing: text(
              "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch."
            ))
          _ = try? await core.saveDayTimes(
            date: todayYMD,
            times: [
              LorvexTaskTime(taskID: created[1].id, time: (9 * 60 + 45)..<(10 * 60 + 30)),
              LorvexTaskTime(taskID: created[2].id, time: (11 * 60)..<(12 * 60 + 30)),
            ])
          _ = try? await core.deferTask(
            id: created[3].id, until: day(1), reason: "not_today",
            note: text("Groceries can wait for the evening"))
        }
      }
      // Park one as Someday.
      if let someday = created.last { _ = try? await core.markTaskSomeday(id: someday.id) }
      // A weekly task and a task that waits on the Someday one, so the task
      // detail's repeat word and its Waits On section have something to show
      // (`lorvex://findtask/<title>` opens either). The weekly task carries the
      // plain rule "Every week" stores, which falls on its deadline's weekday.
      // Neither is planned, so neither appears on Today.
      if let timesheet = try? await core.createTask(
        .init(
          title: text("Submit the weekly timesheet"), listID: work?.id, priority: .p3,
          dueDate: day(4), tags: text(["work"])))
      {
        _ = try? await core.setTaskRecurrence(taskID: timesheet.id, rule: TaskRecurrenceRule(freq: .weekly))
      }
      if let someday = created.last {
        _ = try? await core.createTask(
          .init(
            title: text("Book the offsite venue"), listID: work?.id, priority: .p2,
            tags: text(["work"]), dependsOn: [someday.id]))
      }

      let habits: [(String, String, String, String)] = [
        ("Morning run", "figure.run", "#FF9500", "After waking up"),
        ("Read 30 minutes", "book.fill", "#34C759", "Before bed"),
        ("Meditate", "brain.head.profile", "#5E5CE6", "Mid-morning"),
        ("Review the day", "checklist", "#0A84FF", "Evening"),
      ]
      var createdHabits: [String: LorvexHabit] = [:]
      for (name, icon, color, cue) in habits {
        // Give one habit a personal milestone goal so the goal picker + progress
        // surface have a set value to show.
        let milestoneTarget: Int? = (name == "Read 30 minutes") ? 30 : nil
        if let created = try? await core.createHabit(
          name: text(name), cue: text(cue), icon: icon, color: color, targetCount: 1,
          cadence: .daily, milestoneTarget: milestoneTarget)
        {
          createdHabits[name] = created
        }
      }
      // Backfill completion history so streaks (and the milestone bar) have a
      // real story: a 12-day streak toward the 14-day rung on the goal habit, a
      // shorter 3-day streak on another.
      if let read = createdHabits["Read 30 minutes"] {
        for offset in 0..<12 {
          _ = try? await core.completeHabit(id: read.id, date: ymd.string(from: day(-offset)))
        }
      }
      if let run = createdHabits["Morning run"] {
        for offset in 0..<3 {
          _ = try? await core.completeHabit(id: run.id, date: ymd.string(from: day(-offset)))
        }
      }
      // One archived habit, so the Habits screen's archived section has a row
      // to restore.
      if let journal = try? await core.createHabit(
        name: text("Evening journal"), cue: text("After dinner"), icon: "book.closed", color: "#AF52DE",
        targetCount: 1, cadence: .daily, milestoneTarget: nil)
      {
        _ = try? await core.updateHabit(
          id: journal.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
          archived: true)
      }

      // Events spread across the visible week so the week grid is populated, plus
      // one all-day event to exercise the all-day strip. (dayOffset, title, start, end)
      let events: [(Int, String, String, String)] = [
        (-1, "Sprint planning", "10:00", "11:00"),
        (-1, "Lunch with Sam", "12:30", "13:30"),
        (0, "Team standup", "09:00", "09:30"),
        (0, "1:1 with Alex", "14:00", "14:30"),
        (0, "Design review", "16:30", "17:30"),
        (1, "Customer call", "11:00", "12:00"),
        (2, "Dentist", "08:00", "09:00"),
        (2, "Roadmap sync", "15:00", "16:00"),
        (3, "Morning gym", "07:00", "08:00"),
        (4, "Demo day", "13:00", "14:30"),
      ]
      for (offset, title, start, end) in events {
        _ = try? await core.createCalendarEvent(
          title: text(title), startDate: ymd.string(from: day(offset)), endDate: nil,
          startTime: start, endTime: end, allDay: false, location: nil, notes: nil,
          recurrence: nil, timezone: TimeZone.current.identifier, url: nil, color: nil,
          eventType: nil, personName: nil, attendees: nil)
      }
      _ = try? await core.createCalendarEvent(
        title: text("Team offsite"), startDate: ymd.string(from: day(3)), endDate: nil,
        startTime: nil, endTime: nil, allDay: true, location: nil, notes: nil,
        recurrence: nil, timezone: TimeZone.current.identifier, url: nil, color: nil,
        eventType: nil, personName: nil, attendees: nil)

      // Completed tasks so the Tasks "Completed" filter and done history aren't empty.
      let doneDrafts: [TaskCreateDraft] = [
        .init(title: text("Send the weekly status update"), priority: .p2, tags: text(["work"])),
        .init(title: text("Book the dentist appointment"), priority: .p3, tags: text(["home"])),
      ]
      for draft in doneDrafts {
        if let done = try? await core.createTask(draft) {
          _ = try? await core.completeTask(id: done.id)
        }
      }

      // Memory — durable facts the assistant would remember.
      let memories: [(String, String)] = [
        ("working_hours", "Focuses best 9am–12pm; protect mornings for deep work."),
        ("manager", "Reports to Alex; weekly 1:1 on Mondays."),
        ("writing_style", "Prefers concise, direct updates — no filler."),
        ("current_focus", "Shipping the Apple-native rewrite this quarter."),
      ]
      for (key, content) in memories {
        _ = try? await core.upsertMemory(key: text(key), content: text(content))
      }

      // Daily reviews — today (editable) plus prior days so the weekly digest has history.
      _ = try? await core.upsertDailyReviewPreservingLinks(
        date: todayYMD,
        summary: text("Solid morning of deep work; shipped the planning review."),
        mood: 4, energyLevel: 4,
        wins: text("Unblocked the sync layer; cleared the investor email."),
        blockers: text("Waiting on design sign-off for the calendar grid."),
        learnings: text("Batching reviews before noon keeps the afternoon open."))
      for offset in 1...3 {
        _ = try? await core.upsertDailyReviewPreservingLinks(
          date: ymd.string(from: day(-offset)),
          summary: text("Steady progress across tasks."), mood: 3, energyLevel: 3,
          wins: text("Closed a few items."), blockers: nil, learnings: nil)
      }

      // MetricKit-style diagnostics so the Settings "Recent Diagnostics" feed
      // renders populated. Mapped by the same `MetricKitDiagnosticMapper` the
      // live subscriber uses, so the seeded rows match production shape.
      let sampleDiagnostics: [MetricKitDiagnosticFields] = [
        .init(
          kind: .crash, exceptionType: 1, exceptionCode: 0, signal: 11,
          terminationReason: "Namespace SIGNAL, Code 11 (SIGSEGV)",
          details: #"{"exceptionType":1,"signal":11,"terminationReason":"SIGSEGV"}"#),
        .init(
          kind: .hang, hangDurationSeconds: 3.4,
          details: #"{"hangDurationSeconds":3.4}"#),
        .init(
          kind: .cpuException, cpuTimeSeconds: 21.7,
          details: #"{"totalCPUTimeSeconds":21.7}"#),
      ]
      for fields in sampleDiagnostics {
        let record = MetricKitDiagnosticMapper.record(for: fields)
        _ = try? await core.appendDiagnosticLog(
          source: record.source, level: record.level,
          message: record.message, details: record.details)
      }

      // The feed also carries the app's own errors, which read differently from
      // a MetricKit row: a raw `error_logs.source` eyebrow instead of a
      // localized kind, and a long transport message that has to stay legible
      // truncated. Seed one so a capture exercises that shape too.
      _ = try? await core.appendDiagnosticLog(
        source: "ios.cloud_sync.cycle", level: "error", message: "Cloud sync failed.",
        details:
          "CloudSyncPartialCycleFailure(underlyingError: CKError 26 zoneNotFound: "
          + "Zone 'LorvexZone' not found in database CKDatabase(private))")

      // Fail one queued row so the diagnostics summary renders its retrying
      // depth and the transport error the row is stuck on, the pair that says a
      // backlog is being rejected rather than merely waiting for a cycle.
      if let sync = core as? any EnvelopeSyncServicing,
        let stuck = try? sync.pendingOutbound().first?.outboxId
      {
        try? sync.recordOutboundFailure(
          outboxId: stuck, error: "CKError 26 zoneNotFound: Zone 'LorvexZone' not found",
          kind: .perRecord)
      }

      if LorvexStressSeed.isRequested {
        await LorvexStressSeed.apply(
          to: core, today: todayString(), timezone: TimeZone.current.identifier)
      }

      // A capture of one of Today's edge states moves the sample day into it.
      if let state = LorvexPreviewDayState.requested, let service = core as? SwiftLorvexCoreService {
        try? await state.apply(to: service, text: text)
      }

      await refresh()
    }

    /// Dev/QA only: when `-lorvexDebugBatchTasks` is passed, the Tasks workspace
    /// auto-enters batch selection with a couple of rows pre-selected so the
    /// selection chrome (title count + contextual action bar) can be
    /// screenshotted — that state is otherwise tap-gated.
    public static var debugAutoBatchSelectTasks: Bool {
      CommandLine.arguments.contains("-lorvexDebugBatchTasks")
    }

    /// Dev/QA only: when `-lorvexScrollSettingsToDiagnostics` is passed, the
    /// Settings screen scrolls its bottom-of-list Recent Diagnostics feed into
    /// view on appear so it can be screenshotted without a manual swipe.
    public static var debugScrollSettingsToDiagnostics: Bool {
      CommandLine.arguments.contains("-lorvexScrollSettingsToDiagnostics")
    }

    /// Dev/QA only: when `-lorvexScrollSettingsToDataExport` is passed, the
    /// Settings screen scrolls its Data Export section to the top so a
    /// screenshot shows the export categories row and actions.
    public static var debugScrollSettingsToDataExport: Bool {
      CommandLine.arguments.contains("-lorvexScrollSettingsToDataExport")
    }

    /// Dev/QA only: when `-lorvexScrollHabitDetailToEnd` is passed, a habit's
    /// detail page opens at its end, where its reminders and the Archive and
    /// Delete buttons sit, so they can be screenshotted without a manual swipe.
    public static var debugScrollHabitDetailToEnd: Bool {
      CommandLine.arguments.contains("-lorvexScrollHabitDetailToEnd")
    }

    /// Dev/QA only: when `-lorvexOpenHabitEditor` is passed, a habit's detail
    /// page opens its editor as the Edit button does, so the cadence and
    /// weekday controls can be screenshotted without a tap.
    public static var debugOpenHabitEditor: Bool {
      CommandLine.arguments.contains("-lorvexOpenHabitEditor")
    }

    /// Dev/QA only: when `-lorvexScrollHabitDetailToMiddle` is passed, a habit's
    /// detail page opens centered on the middle of its content, where its
    /// Progress panels sit on a page taller than the screen (at large text
    /// sizes), so they can be screenshotted without a manual swipe.
    public static var debugScrollHabitDetailToMiddle: Bool {
      CommandLine.arguments.contains("-lorvexScrollHabitDetailToMiddle")
    }

    /// Dev/QA only: when `-lorvexScrollReviewToEnd` is passed, the Day and Week
    /// review pages open at their end, where the day rows and the task lists
    /// sit on a page taller than the screen, so they can be screenshotted
    /// without a manual swipe.
    public static var debugScrollReviewToEnd: Bool {
      CommandLine.arguments.contains("-lorvexScrollReviewToEnd")
    }

    /// Dev/QA only: navigate to a `lorvex://` URL passed as the `-lorvexOpenURL`
    /// launch argument, in-process (no SpringBoard "Open in?" confirmation that a
    /// `simctl openurl` would trigger). Lets the redesign screenshot any screen.
    /// A second URL passed as `-lorvexOpenURLLater` is applied two seconds
    /// after the first one has drawn, so a capture can show a screen reached
    /// from a tab that is already on screen (the way a Spotlight, Handoff, or
    /// in-app open pushes it) rather than one set up during launch.
    public func debugApplyLaunchNavigationIfNeeded() {
      let args = CommandLine.arguments
      if let url = Self.debugLaunchURL(named: "-lorvexOpenURL", in: args) {
        debugApplyNavigation(to: url)
      }
      if let later = Self.debugLaunchURL(named: "-lorvexOpenURLLater", in: args) {
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(2))
          debugApplyNavigation(to: later)
        }
      }
    }

    private static func debugLaunchURL(named name: String, in args: [String]) -> URL? {
      guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
      return URL(string: args[index + 1])
    }

    /// The New Event draft the `lorvex://sheet/event/<kind>` hook opens on:
    /// `overnight` runs from 22:00 on `now`'s day to 01:00 the next day, `days`
    /// covers `now`'s day and the two after it as an all-day event, and any
    /// other kind is the next-hour default.
    static func debugEventDraft(kind: String?, now: Date) -> MobileCalendarDraft {
      let calendar = CalendarEventTiming.deviceCalendar
      let day = calendar.startOfDay(for: now)
      switch kind {
      case "overnight":
        let start = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day) ?? now
        return MobileCalendarDraft(
          title: "Night flight", timing: .timed(startingAt: start, minutes: 180))
      case "days":
        let last = calendar.date(byAdding: .day, value: 2, to: day) ?? day
        return MobileCalendarDraft(
          title: "Design conference",
          timing: CalendarEventTiming(start: day, end: last, allDay: true))
      default:
        return MobileCalendarDraft(timing: .nextHourBlock(after: now))
      }
    }

    private func debugApplyNavigation(to url: URL) {
      // `lorvex://tab/<name>` selects a tab, and `lorvex://tab/habits` opens
      // the Habits workspace on the Tasks stack, where the Tasks home's row
      // leads; anything else routes through the normal deep-link handler.
      // `lorvex://tab/<name>/search/<q>` also pre-fills that workspace's search
      // field so its no-results row renders. The calendar opens in the mode
      // the route names, never the one the device remembers, so captures
      // repeat: `lorvex://tab/calendar/week` and `lorvex://tab/calendar/month`
      // open its seven-day grid or its month grid and any other calendar
      // route its day grid; after `day`, `week`, or `month` a `yyyy-MM-dd` day
      // may follow (`lorvex://tab/calendar/month/2026-10-20`).
      // `lorvex://tab/review/week` opens Review on its week digest instead of
      // the day page.
      if url.host == "tab", let name = url.pathComponents.dropFirst().first {
        let components = Array(url.pathComponents.dropFirst())
        if components.count >= 3, components[1] == "search",
          let workspace = MobileDestination(rawValue: name)
        {
          MobileSearchDebugState.initialQuery = (workspace, components[2])
        }
        if name == MobileDestination.habits.rawValue {
          openWorkspaceDestination(.habits)
          return
        }
        if let tab = MobileTab(rawValue: name) {
          if tab == .calendar {
            let mode = components.count >= 2 ? components[1] : ""
            switch mode {
            case "week": calendarPresentationMode = .week
            case "month": calendarPresentationMode = .month
            default: calendarPresentationMode = .grid
            }
            if ["day", "week", "month"].contains(mode), components.count >= 3 {
              calendarPendingDayKey = components[2]
            }
          }
          if tab == .review, components.count >= 2, components[1] == "week" {
            MobileReviewDebugState.initialMode = .weekly
          }
          selectedTab = tab
          return
        }
      }
      // `lorvex://sheet/capture` raises the quick-capture sheet (capture is an
      // action, not a deep-linkable destination — this is a screenshot hook);
      // `lorvex://sheet/capture/<text>` also types <text> into it, so the
      // preview of what Add will create renders. `lorvex://sheet/event` opens
      // the calendar with its New Event sheet raised: `/overnight` on an event
      // from 22:00 to 01:00 the next day, `/days` on an all-day event across
      // three days, and otherwise on the next-hour default.
      if url.host == "sheet", let name = url.pathComponents.dropFirst().first {
        switch name {
        case "capture":
          if url.pathComponents.count > 2 { captureDraft.title = url.pathComponents[2] }
          isPresentingCapture = true
        case "event":
          let kind = url.pathComponents.count > 2 ? url.pathComponents[2] : nil
          MobileCalendarDebugState.initialCreateDraft = Self.debugEventDraft(kind: kind, now: now())
          selectedTab = .calendar
        default: break
        }
        return
      }
      // `lorvex://dest/<rawValue>` opens a destination with no public deep
      // link the way the current layout reaches it (Settings on the Today
      // stack, Memory on the Tasks stack, or the sidebar's Workspaces group) —
      // a screenshot hook.
      if url.host == "dest", let name = url.pathComponents.last,
        let destination = MobileDestination(rawValue: name)
      {
        openWorkspaceDestination(destination)
        return
      }
      // `lorvex://memorycomposer` opens Memory with its New Memory sheet raised
      // (the sheet is otherwise tap-gated); `/filled` also seeds a draft so the
      // enabled Save button renders — a screenshot hook.
      if url.host == "memorycomposer" {
        if url.pathComponents.last == "filled" {
          memoryKeyDraft = "travel_preferences"
          memoryContentDraft = "Prefers window seats and morning flights; avoids red-eyes."
        }
        MobileMemoryDebugState.presentsComposerOnAppear = true
        openWorkspaceDestination(.memory)
        return
      }
      // `lorvex://milestonecelebration` stages a sample milestone celebration so
      // the floating badge overlay can be screenshotted (a crossing is otherwise
      // only reachable by tapping a habit into a new milestone) — a screenshot hook.
      if url.host == "milestonecelebration" {
        milestoneCelebration = MobileHabitMilestoneCelebration(
          habitName: "Read 30 minutes", milestone: 14, metric: "streak",
          frequencyType: "daily", tint: Color(lorvexHex: "#34C759") ?? .green)
        return
      }
      // `lorvex://firsttask` opens the first seeded task's detail on the Today
      // stack (we don't know seeded IDs ahead of time) — a screenshot hook.
      // `lorvex://firsttask/compose/<checklist|reminder>` also unfolds one of the
      // detail's inline composers, and `lorvex://firsttask/field/<field>` raises
      // one sentence word's editor (`waitsOn`, `due`, …); both are otherwise
      // tap-gated.
      if url.host == "firsttask",
        let id = snapshot.today.tasks.first?.id
      {
        let components = url.pathComponents
        if components.count >= 3, components[1] == "compose" {
          MobileTaskDetailDebugState.initialComposer =
            MobileTaskDetailDebugState.Composer(rawValue: components[2])
        }
        if components.count >= 3, components[1] == "field" {
          MobileTaskDetailDebugState.initialField = MobileTaskField(rawValue: components[2])
        }
        navigate(to: .task(id))
        return
      }
      // `lorvex://findtask/<title>` opens the seeded task with that title on
      // the Today stack, for a task detail that is not first on Today (a
      // repeating task, one with dependencies) — a screenshot hook;
      // `lorvex://findtask/<title>/field/<field>` also raises one field's
      // editor, as `firsttask` does. The title is the seed's English one and
      // is translated the way the seed wrote it.
      if url.host == "findtask", url.pathComponents.count >= 2 {
        let components = url.pathComponents
        if components.count >= 4, components[2] == "field" {
          MobileTaskDetailDebugState.initialField = MobileTaskField(rawValue: components[3])
        }
        let seededTitle = LorvexSampleText(language: .running)(components[1])
        Task { @MainActor in
          guard
            let page = try? await core.listTasks(
              status: "all", listID: nil, priority: nil, text: seededTitle, limit: 1, offset: 0),
            let id = page.tasks.first?.id
          else { return }
          navigate(to: .task(id))
        }
        return
      }
      // Screenshot hooks for the first seeded habit and memory entry.
      // `lorvex://firsthabit` opens the habit the way a habit deep link does;
      // `lorvex://firsthabit/select` opens Habits with it selected, which the
      // iPad split shows in its detail pane. `lorvex://firstmemory` opens
      // Memory with the entry selected, and `lorvex://firstmemory/push` pushes
      // its detail screen instead, the way a row tap does at compact width.
      if url.host == "firsthabit" {
        let selects = url.pathComponents.last == "select"
        Task { @MainActor in
          if habits == nil { await refresh() }
          guard let id = habits?.habits.first?.id else { return }
          if selects {
            openWorkspaceDestination(.habits)
            selectHabit(id)
          } else {
            navigate(to: .habit(id))
          }
        }
        return
      }
      if url.host == "firstmemory" {
        openWorkspaceDestination(.memory)
        let pushes = url.pathComponents.last == "push"
        Task { @MainActor in
          if memory == nil { await loadMemorySnapshot() }
          guard let id = memory?.entries.first?.id else { return }
          if pushes {
            tasksRoutePath.append(.memoryEntry(id))
          } else {
            selectMemoryEntry(id)
          }
        }
        return
      }
      // `lorvex://taskscope/<all|scheduled|priority|someday|completed|list|describedlist|emptylist>`
      // drills the Tasks home into a scope so the otherwise tap-gated scoped
      // list can be screenshotted. `list` picks the first seeded list,
      // `describedlist` the first with a description, and `emptylist` the first
      // with no open tasks.
      if url.host == "taskscope", let name = url.pathComponents.last {
        let scope: MobileTasksScope?
        switch name {
        case "all": scope = .all
        case "scheduled": scope = .scheduled
        case "priority": scope = .priority
        case "someday": scope = .someday
        case "completed": scope = .completed
        case "list": scope = lists?.lists.first.map { .list($0.id) }
        case "describedlist":
          scope = lists?.lists.first { !($0.description ?? "").isEmpty }.map { .list($0.id) }
        case "emptylist": scope = lists?.lists.first { $0.openCount == 0 }.map { .list($0.id) }
        default: scope = nil
        }
        if let scope {
          selectedTab = .tasks
          tasksRoutePath = [.tasksScope(scope)]
        }
        return
      }
      openDeepLink(url)
    }
  }
#endif
