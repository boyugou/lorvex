#if DEBUG
  import Foundation
  import LorvexCore
  import SwiftUI

  extension MobileStore {
    /// Dev/QA only: seed a realistic sample dataset so populated layouts can be
    /// inspected in the simulator during the UI redesign. Triggered by the
    /// `-lorvexSeedSampleData` launch argument and no-ops unless the store is
    /// empty, so relaunching never duplicates. Compiled out of release builds.
    /// Writes through the normal core path (valid HLC / changelog), never a
    /// preview/in-memory backend.
    public func debugSeedSampleDataIfNeeded() async {
      guard CommandLine.arguments.contains("-lorvexSeedSampleData") else { return }
      guard
        let existing = try? await core.listTasks(
          status: "all", listID: nil, priority: nil, text: nil, limit: 1, offset: 0),
        existing.tasks.isEmpty
      else { return }

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
        name: "Work", description: "Day job & deep work", color: "#0A84FF", icon: "briefcase.fill")
      let personal = try? await core.createList(
        name: "Personal", description: nil, color: "#34C759", icon: "house.fill")
      _ = try? await core.createList(
        name: "Reading", description: "Papers & books", color: "#AF52DE", icon: "book.fill")

      let drafts: [TaskCreateDraft] = [
        .init(
          title: "Reply to the investor update email", priority: .p1,
          dueDate: day(-1), plannedDate: day(-1), tags: ["work", "urgent"]),
        .init(
          title: "Review the Q3 planning doc", listID: work?.id, priority: .p1,
          estimatedMinutes: 45, dueDate: day(0), plannedDate: day(0), tags: ["work"]),
        .init(
          title: "Refactor the sync layer", listID: work?.id, priority: .p2,
          estimatedMinutes: 90, plannedDate: day(0), tags: ["engineering"]),
        .init(
          title: "Buy groceries for the week", listID: personal?.id, priority: .p2,
          plannedDate: day(0), tags: ["home"]),
        .init(title: "Read the GRPO paper", priority: .p2, tags: ["research"]),
        .init(title: "Renew passport", priority: .p3, dueDate: day(5)),
        .init(title: "Plan the spring offsite", priority: .p3, tags: ["someday"]),
      ]
      var created: [LorvexTask] = []
      for draft in drafts {
        if let task = try? await core.createTask(draft) { created.append(task) }
      }
      // Put a couple of today's tasks in the current focus plan.
      if created.count >= 3 {
        _ = try? await core.addToCurrentFocus(
          date: todayYMD,
          taskIDs: [created[1].id, created[2].id],
          briefing: "Ship the planning review and unblock sync.",
          timezone: TimeZone.current.identifier)
      }
      // Park one as Someday.
      if let someday = created.last { _ = try? await core.markTaskSomeday(id: someday.id) }

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
          name: name, cue: cue, icon: icon, color: color, targetCount: 1,
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
          title: title, startDate: ymd.string(from: day(offset)), endDate: nil,
          startTime: start, endTime: end, allDay: false, location: nil, notes: nil,
          recurrence: nil, timezone: TimeZone.current.identifier, url: nil, color: nil,
          eventType: nil, personName: nil, attendees: nil)
      }
      _ = try? await core.createCalendarEvent(
        title: "Team offsite", startDate: ymd.string(from: day(3)), endDate: nil,
        startTime: nil, endTime: nil, allDay: true, location: nil, notes: nil,
        recurrence: nil, timezone: TimeZone.current.identifier, url: nil, color: nil,
        eventType: nil, personName: nil, attendees: nil)

      // Completed tasks so the Tasks "Completed" filter and done history aren't empty.
      let doneDrafts: [TaskCreateDraft] = [
        .init(title: "Send the weekly status update", priority: .p2, tags: ["work"]),
        .init(title: "Book the dentist appointment", priority: .p3, tags: ["home"]),
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
      for (key, content) in memories { _ = try? await core.upsertMemory(key: key, content: content) }

      // Daily reviews — today (editable) plus prior days so the weekly digest has history.
      _ = try? await core.upsertDailyReviewPreservingLinks(
        date: todayYMD,
        summary: "Solid morning of deep work; shipped the planning review.",
        mood: 4, energyLevel: 4,
        wins: "Unblocked the sync layer; cleared the investor email.",
        blockers: "Waiting on design sign-off for the calendar grid.",
        learnings: "Batching reviews before noon keeps the afternoon open.")
      for offset in 1...3 {
        _ = try? await core.upsertDailyReviewPreservingLinks(
          date: ymd.string(from: day(-offset)),
          summary: "Steady progress across tasks.", mood: 3, energyLevel: 3,
          wins: "Closed a few items.", blockers: nil, learnings: nil)
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

      await refreshResettingCloudSyncPacing()
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

    /// Dev/QA only: navigate to a `lorvex://` URL passed as the `-lorvexOpenURL`
    /// launch argument, in-process (no SpringBoard "Open in?" confirmation that a
    /// `simctl openurl` would trigger). Lets the redesign screenshot any screen.
    public func debugApplyLaunchNavigationIfNeeded() {
      let args = CommandLine.arguments
      guard
        let index = args.firstIndex(of: "-lorvexOpenURL"), index + 1 < args.count,
        let url = URL(string: args[index + 1])
      else { return }
      // `lorvex://tab/<name>` selects a primary tab (e.g. show the More list);
      // anything else routes through the normal deep-link handler.
      if url.host == "tab", let name = url.pathComponents.last,
        let tab = MobileTab(rawValue: name)
      {
        selectedTab = tab
        return
      }
      // `lorvex://sheet/capture` raises the quick-capture sheet (capture is an
      // action, not a deep-linkable destination — this is a screenshot hook).
      if url.host == "sheet", let name = url.pathComponents.last {
        switch name {
        case "capture": isPresentingCapture = true
        default: break
        }
        return
      }
      // `lorvex://dest/<rawValue>` pushes a More-tab workspace (Settings, Memory,
      // Review) that has no public deep link — a screenshot hook.
      if url.host == "dest", let name = url.pathComponents.last,
        let destination = MobileDestination(rawValue: name)
      {
        openMoreDestination(destination)
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
      if url.host == "firsttask",
        let id = snapshot.nextTask?.id ?? snapshot.todayTasks.first?.id
      {
        openNavigationTarget(
          MobileNavigationTarget(selectedTab: .today, route: .task(id)))
        return
      }
      // `lorvex://listdetail` pushes the first seeded list's detail on the Tasks
      // stack (`/empty` targets a zero-task list) — a screenshot hook for the
      // list-detail header + empty state.
      if url.host == "listdetail" {
        let wantEmpty = url.pathComponents.last == "empty"
        let id =
          wantEmpty
          ? lists?.lists.first(where: { $0.openCount == 0 })?.id
          : lists?.lists.first?.id
        if let id {
          selectedTab = .tasks
          tasksRoutePath = [.list(id)]
        }
        return
      }
      // `lorvex://taskscope/<all|scheduled|priority|someday|completed|list>` drills
      // the Tasks home into a scope (the `list` form picks the first seeded list)
      // so the otherwise tap-gated scoped list can be screenshotted.
      if url.host == "taskscope", let name = url.pathComponents.last {
        let scope: MobileTasksScope?
        switch name {
        case "all": scope = .all
        case "scheduled": scope = .scheduled
        case "priority": scope = .priority
        case "someday": scope = .someday
        case "completed": scope = .completed
        case "list": scope = lists?.lists.first.map { .list($0.id) }
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
