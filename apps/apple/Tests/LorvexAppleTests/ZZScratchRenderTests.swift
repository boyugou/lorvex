#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import LorvexApple
  @testable import LorvexCore
  @testable import LorvexMobile

  // Throwaway visual QA harness; not committed.
  @Suite(.enabled(if: ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] != nil))
  @MainActor
  struct ZZScratchRenderTests {
    @Test func habitInspectors() async throws {
      let store = AppStore(core: try await makeSeededInMemoryCore())
      await store.refresh()

      store.beginCreateHabitDraft()
      store.draftHabitName = "Drink water"
      store.draftHabitCue = "A glass with every meal"
      store.draftHabitTargetCountText = "6"
      await store.createDraftHabit()

      store.beginCreateHabitDraft()
      store.draftHabitName = "Strength training"
      store.draftHabitCadenceMode = .weekly
      store.draftHabitWeekdays = [0, 2, 4]
      store.draftHabitMilestoneTargetText = "12"
      await store.createDraftHabit()

      let habits = store.habits?.habits ?? []
      let water = try #require(habits.first { $0.name == "Drink water" })
      let gym = try #require(habits.first { $0.name == "Strength training" })

      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .current
      let parts = store.logicalTodayDateString.split(separator: "-").compactMap { Int($0) }
      let today = try #require(calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])))
      func key(_ offset: Int) -> (String, Int) {
        let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return (
          String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
          calendar.component(.weekday, from: day)
        )
      }

      // Water: a varying count each day for 40 days, three so far today.
      for offset in 0..<40 {
        let (date, _) = key(offset)
        let count = offset == 0 ? 3 : [6, 4, 6, 2, 5, 6, 1, 6, 3, 6][offset % 10]
        for _ in 0..<count { _ = try await store.core.completeHabit(id: water.id, date: date) }
      }
      // Strength: Mondays, Wednesdays, and Fridays for six weeks, a few
      // Fridays missed, and one off-plan Saturday.
      for offset in 1..<42 {
        let (date, weekday) = key(offset)
        let planned = [2, 4, 6].contains(weekday)
        let missed = weekday == 6 && offset % 3 == 0
        if (planned && !missed) || (weekday == 7 && (7...13).contains(offset)) {
          _ = try await store.core.completeHabit(id: gym.id, date: date)
        }
      }
      await store.refresh()
      await store.loadAllHabitStats()

      for (habit, name) in [(water, "habit-water"), (gym, "habit-strength")] {
        store.selection = .habits
        store.selectedHabitID = habit.id
        await store.loadHabitDetail(id: habit.id)
        for width in [320, 220] as [CGFloat] {
          try await render(
            HabitDetailInspector(store: store, habitID: habit.id)
              .frame(width: width, height: 1180),
            named: "\(name)-\(Int(width))")
        }
      }
    }

    @Test func blockFit() async throws {
      func height(_ view: some View) -> CGFloat {
        NSHostingView(rootView: view.fixedSize()).fittingSize.height
      }
      let font = LorvexDesign.Typography.tertiaryText
      for (label, text) in [("latin", "Team standup"), ("deva", "टीम स्टैंडअप"), ("time-hi", "पू 9:30–9:45"), ("mixed", "Team पू")] {
        print("LINEHEIGHT \(label) regular=\(height(Text(text).font(font))) semibold=\(height(Text(text).font(font.weight(.semibold)))) caption2=\(height(Text(text).font(.caption2)))")
      }
      let samples: [(String, String, String)] = [
        ("Team standup", "9:30 AM", "9:30 – 9:45 AM"),
        ("टीम स्टैंडअप बैठक", "पू 9:30", "पू 9:30–9:45"),
        ("Draft the team offsite agenda", "पू 9:45", "पू 9:45–10:45"),
      ]
      let heights: [CGFloat] = [12, 16, 20, 24, 30, 36, 48]
      let view = VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
          HStack(alignment: .top, spacing: 8) {
            ForEach(heights, id: \.self) { h in
              VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(h))").font(.caption2)
                LorvexCalendarBlockText(title: sample.0, time: sample.1, range: sample.2)
                  .padding(.horizontal, 4)
                  .frame(width: 110, height: h, alignment: .topLeading)
                  .clipped()
                  .background(Color.green.opacity(0.16))
                LorvexCalendarBlockText(title: sample.0, time: sample.1, range: sample.2) {
                  Image(systemName: "circle")
                    .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                }
                  .padding(.leading, 3).padding(.trailing, 4)
                  .frame(width: 110, height: h, alignment: .topLeading)
                  .clipped()
                  .background(Color.orange.opacity(0.16))
              }
            }
          }
        }
      }
      try await render(view, named: "block-fit")
    }

    @Test func importSummary() async throws {
      func task(_ id: String, _ title: String) -> LorvexImportIssue.Record { .named(id: id, name: title) }
      let mixed = LorvexImportSummary(
        results: [
          LorvexImportCategoryResult(category: .lists, imported: 4, skipped: 1),
          LorvexImportCategoryResult(category: .tasks, imported: 38, skipped: 6),
          LorvexImportCategoryResult(category: .dailyReviews, imported: 11, skipped: 0),
          LorvexImportCategoryResult(category: .calendarEvents, imported: 0, skipped: 0),
        ],
        issues: [
          LorvexImportIssue(category: .tasks, record: task("t1", "Renew passport before the trip"), outcome: .notImported, detail: ""),
          LorvexImportIssue(category: .dailyReviews, record: .day("2026-09-28"), outcome: .notImported, detail: ""),
          LorvexImportIssue(category: .calendarEvents, record: .wholeCategory, outcome: .notImported, detail: ""),
          LorvexImportIssue(category: .tasks, record: task("t2", "Water the plants"), outcome: .restoredWithout(.recurrence), detail: ""),
          LorvexImportIssue(category: .tasks, record: task("t2", "Water the plants"), outcome: .restoredWithout(.reminders), detail: ""),
          LorvexImportIssue(category: .tasks, record: task("t3", "Quarterly report"), outcome: .restoredWithout(.dependencies), detail: ""),
          LorvexImportIssue(category: .tasks, record: task("t3", "Quarterly report"), outcome: .restoredWithout(.history), detail: ""),
          LorvexImportIssue(category: .tasks, record: task("t4", "Call the bank"), outcome: .restoredWithout(.plannedTime), detail: ""),
        ])
      let failed = LorvexImportSummary(
        results: [LorvexImportCategoryResult(category: .memory, imported: 0, skipped: 0)],
        issues: [LorvexImportIssue(category: .memory, record: .named(id: "prefs", name: "prefs.morning"), outcome: .notImported, detail: "")])
      let view = VStack(alignment: .leading, spacing: 28) {
        ImportSummaryView(mixed)
        ImportSummaryView(failed)
        ImportSummaryView(LorvexImportSummary(rejection: .invalidNativeTaskGraph("x")))
      }
      .frame(width: 380, alignment: .leading)
      .padding(16)
      .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
      try await render(view, named: "import-summary")
    }

    @Test func typesettingProbe() async throws {
      let glues: [(String, String)] = [
        ("plain", ""), ("WJ", "\u{2060}"), ("ZWJ", "\u{200D}"), ("FEFF", "\u{FEFF}"),
      ]
      let widths: [CGFloat] = [60, 64]
      let view = HStack(alignment: .top, spacing: 10) {
        ForEach(glues, id: \.0) { glue in
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(glue.0) verbatim").font(.caption2.bold()).foregroundStyle(.red)
            ForEach(widths, id: \.self) { width in
              Text(verbatim: "오전 10:30" + glue.1 + "까지")
                .font(.footnote).lineLimit(3)
                .typesettingLanguage(Locale.Language(identifier: "ko"))
                .frame(width: width, alignment: .leading).border(Color.gray.opacity(0.3))
            }
            Text(verbatim: "\(glue.0) key").font(.caption2.bold()).foregroundStyle(.blue)
            ForEach(widths, id: \.self) { width in
              Text("오전 10:30\(glue.1)까지")
                .font(.footnote).lineLimit(3)
                .typesettingLanguage(Locale.Language(identifier: "ko"))
                .frame(width: width, alignment: .leading).border(Color.gray.opacity(0.3))
            }
            Text(verbatim: "\(glue.0) attributed").font(.caption2.bold()).foregroundStyle(.green)
            ForEach(widths, id: \.self) { width in
              Text(AttributedString("오전 10:30" + glue.1 + "까지"))
                .font(.footnote).lineLimit(3)
                .typesettingLanguage(Locale.Language(identifier: "ko"))
                .frame(width: width, alignment: .leading).border(Color.gray.opacity(0.3))
            }
          }
        }
      }
      try await render(view, named: "probe-paths")
    }

    @Test func calendarEventEditors() async throws {
      let store = AppStore(core: try await makeSeededInMemoryCore())
      await store.refresh()
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .current
      func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))
          ?? Date()
      }
      func sheet(_ mode: CalendarEventSheet.Mode) -> some View {
        CalendarEventSheet(store: store, mode: mode, dismiss: {}).frame(width: 540, height: 760)
      }

      store.beginCreateCalendarDraft()
      store.draftCalendarTitle = "Night flight"
      store.draftCalendarTiming = CalendarEventTiming(start: at(2, 22), end: at(3, 1), allDay: false)
      try await render(sheet(.create), named: "event-create-overnight")

      store.draftCalendarTitle = "Design conference"
      store.draftCalendarTiming = CalendarEventTiming(start: at(5, 9), end: at(7, 10), allDay: true)
      try await render(sheet(.create), named: "event-create-days")

      store.draftCalendarTitle = "Review"
      store.draftCalendarTiming = CalendarEventTiming(start: at(5, 14), end: at(4, 15), allDay: false)
      try await render(sheet(.create), named: "event-create-invalid")

      let shift = try await store.core.createCalendarEvent(
        title: "Night shift", startDate: "2026-10-02", endDate: "2026-10-03",
        startTime: "22:00", endTime: "06:00", allDay: false, location: "Ward 3", notes: nil)
      store.prepareCalendarDraft(for: shift)
      try await render(sheet(.edit(shift)), named: "event-edit-overnight")

      let trip = try await store.core.createCalendarEvent(
        title: "Design conference", startDate: "2026-10-05", endDate: "2026-10-07",
        startTime: nil, endTime: nil, allDay: true, location: "Lisbon", notes: nil)
      let late = try await store.core.createCalendarEvent(
        title: "Late session", startDate: "2026-10-02", endDate: "2026-10-03",
        startTime: "21:00", endTime: "00:00", allDay: false, location: nil, notes: nil)
      let inspectors = HStack(alignment: .top, spacing: 16) {
        CalendarEventInspector(event: shift, edit: {}, requestDelete: {}, close: {})
        CalendarEventInspector(event: trip, edit: {}, requestDelete: {}, close: {})
        CalendarEventInspector(event: late, edit: {}, requestDelete: {}, close: {})
      }
      .frame(height: 420)
      try await render(inspectors, named: "event-inspectors")
    }

    @Test func diagnosticsChangelogSection() async throws {
      let core = try await makeSeededInMemoryCore()
      let store = AppStore(core: core)
      await store.refresh()
      _ = await store.saveChangelogRetentionPolicy(.days(30))
      await store.loadRuntimeDiagnostics()
      func rows() throws -> Int {
        try core.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0 }
      }
      let before = try rows()
      let form = Form {
        SettingsChangelogSection(store: store)
      }
      .formStyle(.grouped)
      .frame(width: 640, height: 300)
      try await render(form, named: "diag-changelog")
      try await Task.sleep(for: .milliseconds(500))
      let after = try rows()
      print("SCRATCH ai_changelog rows before=\(before) after=\(after)")
      #expect(before == after)
    }

    @Test func calendarOvernightGrid() async throws {
      let core = try await makeSeededInMemoryCore()
      let calendar = CalendarEventTiming.deviceCalendar
      let today = calendar.startOfDay(for: Date())
      func key(_ offset: Int) -> String {
        LorvexDateFormatters.ymd.string(
          from: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
      }
      _ = try await core.createCalendarEvent(
        title: "Night flight", startDate: key(0), endDate: key(1), startTime: "22:30",
        endTime: "01:30", allDay: false, location: nil, notes: nil)
      _ = try await core.createCalendarEvent(
        title: "Conference trip", startDate: key(2), endDate: key(4), startTime: "19:00",
        endTime: "09:00", allDay: false, location: nil, notes: nil)
      _ = try await core.createCalendarEvent(
        title: "Late session", startDate: key(1), endDate: key(2), startTime: "21:00",
        endTime: "00:00", allDay: false, location: nil, notes: nil)
      _ = try await core.createCalendarEvent(
        title: "Standup", startDate: key(1), endDate: nil, startTime: "09:00",
        endTime: "09:30", allDay: false, location: nil, notes: nil)
      let store = AppStore(core: core)
      await store.refresh()
      let weekStart = calendar.date(byAdding: .day, value: -1, to: today) ?? today
      for width in [1100, 760] {
        let grid = CalendarWeekGridView(
          store: store, weekStart: weekStart, selectEvent: { _ in }, openTask: { _ in },
          createAt: { _, _, _ in }
        )
        .frame(width: CGFloat(width), height: 260)
        try await render(grid, named: "grid-overnight-\(width)")
      }
    }

    @Test func mobileOvernightColumn() async throws {
      let calendar = CalendarEventTiming.deviceCalendar
      let today = calendar.startOfDay(for: Date())
      func key(_ offset: Int) -> String {
        LorvexDateFormatters.ymd.string(
          from: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
      }
      func event(
        _ id: String, _ title: String, _ start: Int, _ startTime: String, _ end: Int?,
        _ endTime: String
      ) -> CalendarTimelineEvent {
        CalendarTimelineEvent(
          id: id, title: title, source: "lorvex", editable: true, startDate: key(start),
          startTime: startTime, endDate: end.map(key), endTime: endTime, allDay: false,
          location: nil, color: nil, eventType: "event", timezone: nil, isRecurring: false)
      }
      let events = [
        event("flight", "Night flight", 0, "22:30", 1, "01:30"),
        event("late", "Late session", 1, "21:00", 2, "00:00"),
        event("trip", "Conference trip", 0, "18:00", 2, "09:00"),
        event("standup", "Standup", 1, "09:00", nil, "09:30"),
      ]
      func column(days: Int, from start: Date) -> some View {
        MobileCalendarDayColumn(
          startDate: start, dayCount: days, events: events, tasks: [], calendar: calendar,
          onTapEvent: { _ in }, deletion: .inert, onTapTask: { _ in },
          onDropTask: { _, _ in }, onTapEmpty: { _, _ in }, onReschedule: nil)
      }
      try await render(column(days: 3, from: today).frame(width: 900, height: 1500), named: "mobile-3day")
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
      try await render(column(days: 1, from: tomorrow).frame(width: 402, height: 1450), named: "mobile-day")
    }

    @Test func todayOvernightSchedule() async throws {
      let day = "2026-05-23"
      func event(
        _ id: String, _ title: String, _ startDate: String, _ startTime: String?, _ endDate: String?,
        _ endTime: String?, allDay: Bool = false, color: String? = nil, location: String? = nil
      ) -> CalendarTimelineEvent {
        CalendarTimelineEvent(
          id: id, title: title, source: "lorvex", editable: true, startDate: startDate,
          startTime: startTime, endDate: endDate, endTime: endTime, allDay: allDay,
          location: location, color: color, eventType: "event", timezone: nil, isRecurring: false)
      }
      let events = [
        event("holiday", "Founders' Day", day, nil, day, nil, allDay: true, color: "#34C759"),
        event("trip", "Conference trip", "2026-05-22", "18:00", "2026-05-24", "09:00", color: "#AF52DE"),
        event("flight", "Night flight", "2026-05-22", "22:30", day, "01:30", color: "#FF9500", location: "SFO"),
        event("standup", "Standup", day, "09:00", nil, "09:30", color: "#007AFF"),
        event("late", "Late session", day, "21:00", "2026-05-24", "00:00", color: "#FF2D55"),
        event("redeye", "Redeye home", day, "22:30", "2026-05-24", "01:30", color: "#5AC8FA"),
      ]
      let rows = LorvexTodayTimeline.build(day: day, events: events, tasks: [], times: [:], nowMinutes: 60)
      let appStore = AppStore(core: try await makeSeededInMemoryCore())
      let mac = TodayScheduleSection(store: appStore, rows: rows, nowMinutes: 60, items: [:])
        .frame(width: 520)
      try await render(mac, named: "today-mac")
      let mobileStore = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { day })
      let phone = VStack(alignment: .leading, spacing: 6) {
        MobileTodayScheduleTimelineSection(store: mobileStore, items: rows)
      }
      .frame(width: 370)
      try await render(phone, named: "today-phone")
    }

    @Test func agendaOvernightLists() async throws {
      func event(
        _ id: String, _ title: String, _ startDate: String, _ startTime: String?, _ endDate: String?,
        _ endTime: String?, allDay: Bool = false, color: String? = nil
      ) -> CalendarTimelineEvent {
        CalendarTimelineEvent(
          id: id, title: title, source: "lorvex", editable: true, startDate: startDate,
          startTime: startTime, endDate: endDate, endTime: endTime, allDay: allDay,
          location: id == "flight" ? "SFO" : nil, color: color, eventType: "event", timezone: nil,
          isRecurring: false)
      }
      let events = [
        event("flight", "Night flight", "2026-05-24", "22:30", "2026-05-25", "01:30", color: "#FF9500"),
        event("trip", "Conference trip", "2026-05-25", "18:00", "2026-05-27", "09:00", color: "#AF52DE"),
        event("standup", "Standup", "2026-05-25", "09:00", nil, "09:30", color: "#007AFF"),
        event("late", "Late session", "2026-05-24", "21:00", "2026-05-25", "00:00", color: "#FF2D55"),
        event("holiday", "Founders' Day", "2026-05-26", nil, "2026-05-26", nil, allDay: true, color: "#34C759"),
      ]
      let days = LorvexAgendaDay.build(todayKey: "2026-05-23", events: events, tasks: [])
      let menu = MenuBarAgendaList(
        days: days, todayKey: "2026-05-23", complete: { _ in }, open: { _ in }, openEvent: { _, _ in })
        .frame(width: 320)
      try await render(menu, named: "agenda-menubar")
      let tomorrow = LorvexReviewTomorrow(
        label: "Tomorrow", day: days.first { $0.key == "2026-05-25" }, emptyLine: "Nothing planned",
        allDay: TodayCalmCopy.allDay, timeRange: TodayCalmCopy.timeRange(start:end:),
        identifier: "scratch.tomorrow", openTask: { _ in }
      )
      .frame(width: 420)
      try await render(tomorrow, named: "agenda-tomorrow")
      let ahead = LorvexReviewWeekAhead(
        days: days,
        words: .init(
          label: "Week Ahead", emptyLine: "Nothing planned", allDay: TodayCalmCopy.allDay,
          dayLabel: { $0 }, moreLine: { "\($0) more" }, timeRange: TodayCalmCopy.timeRange(start:end:)),
        identifier: "scratch.ahead", openTask: { _ in }
      )
      .frame(width: 480)
      try await render(ahead, named: "agenda-weekahead")
      let rows = VStack(alignment: .leading, spacing: 0) {
        ForEach(["2026-05-24", "2026-05-25", "2026-05-26"], id: \.self) { key in
          Text(key).font(.headline).padding(.top, 8)
          ForEach(events.filter { $0.occurs(on: key) }, id: \.id) { event in
            MobileCalendarAgendaRow(event: event, dayKey: key)
          }
        }
      }
      .frame(width: 370)
      try await render(rows, named: "agenda-mobile-rows")
    }

    @Test func weekdayHeaderProbe() async throws {
      let cases: [(String, String)] = [
        ("Par jour de la semaine", "Depuis le 20 juil."),
        ("Per giorno della settimana", "Ultime 12 settimane"),
        ("By Weekday", "Last 12 weeks"),
      ]
      func title(_ text: String) -> some View {
        Label(text, systemImage: "chart.bar.xaxis")
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)
      }
      func caption(_ text: String) -> some View {
        Text(text)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      let column = VStack(alignment: .leading, spacing: 18) {
        ForEach(Array(cases.enumerated()), id: \.offset) { _, pair in
          let (t, c) = pair
          // A: current
          HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
            title(t)
            Spacer(minLength: LorvexDesign.Spacing.s)
            caption(c)
          }
          .frame(width: 244).border(.red.opacity(0.3))
          // B: fallback stacks under the icon
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
              title(t)
              Spacer(minLength: LorvexDesign.Spacing.s)
              caption(c)
            }
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
              title(t)
              caption(c)
            }
          }
          .frame(width: 244, alignment: .leading).border(.blue.opacity(0.3))
          // C: fallback caption aligned with the title text
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
              title(t)
              Spacer(minLength: LorvexDesign.Spacing.s)
              caption(c)
            }
            Label {
              VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
                Text(t).lineLimit(1)
                caption(c)
              }
            } icon: {
              Image(systemName: "chart.bar.xaxis")
            }
            .font(LorvexDesign.Typography.primaryEmphasis)
          }
          .frame(width: 244, alignment: .leading).border(.green.opacity(0.3))
        }
      }
      try await render(column, named: "weekday-header-probe")
    }

    @Test func plannedAfterDeadlineInspector() async throws {
      let core = try await makeSeededInMemoryCore()
      let store = AppStore(core: core)
      await store.refresh()
      var draft = TaskCreateDraft(title: "Book the offsite venue", notes: "Compare the two venues.")
      draft.plannedDate = try store.storageDate(daysFromLogicalToday: 1)
      draft.dueDate = try store.storageDate(daysFromLogicalToday: 0)
      draft.estimatedMinutes = 60
      let task = try await core.createTask(draft)
      await store.refresh()
      store.selectTaskFromList(task.id)
      try await Task.sleep(for: .milliseconds(300))
      try await render(TaskDetailView(store: store).frame(width: 320, height: 640), named: "planned-after-deadline")
    }

    func render(_ content: some View, named name: String) async throws {
      let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"]))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let hosting = NSHostingView(
          rootView: content.padding(24).background(Color(nsColor: .underPageBackgroundColor)).fixedSize())
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(
          contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(
          NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.contentView = nil
        try #require(rep.representation(using: .png, properties: [:]))
          .write(to: directory.appendingPathComponent("\(name)-\(label).png"))
      }
    }
  }

  /// Experiment: measured layout, then a scaled one-line title as the last resort.
  struct ScaledLastResort: View {
    let title: String
    let time: String?
    let timeRange: String?
    var body: some View {
      ViewThatFits(in: .vertical) {
        VStack(alignment: .leading, spacing: 1) {
          titleText.lineLimit(2).fixedSize(horizontal: false, vertical: true)
          if let time { timeLine(time) }
        }
        .padding(.vertical, 2)
        VStack(alignment: .leading, spacing: 1) {
          titleText.lineLimit(1)
          if let time { timeLine(time) }
        }
        .padding(.vertical, 2)
        ViewThatFits(in: .horizontal) {
          if let time {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
              titleText.lineLimit(1)
              timeText(timeRange ?? time)
            }
          }
          titleText.lineLimit(1)
        }
        .padding(.vertical, 1)
        titleText.lineLimit(1).minimumScaleFactor(0.5)
          .frame(maxHeight: .infinity, alignment: .leading)
      }
    }
    private var titleText: some View {
      Text(title).font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
    }
    private func timeLine(_ time: String) -> some View {
      ViewThatFits(in: .horizontal) {
        if let timeRange { timeText(timeRange) }
        timeText(time)
      }
    }
    private func timeText(_ label: String) -> some View {
      Text(label).font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
        .monospacedDigit().lineLimit(1).fixedSize()
    }
  }
#endif

