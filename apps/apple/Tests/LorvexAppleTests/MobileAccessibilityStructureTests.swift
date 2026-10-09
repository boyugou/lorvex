import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// The VoiceOver structure of phone surfaces whose elements are built from
/// several views: a block that reads twice, a decorative glyph that reads as
/// "Selected", an editor without a name. A unit test cannot host the
/// accessibility tree, so the modifiers that give each surface its structure
/// are pinned in the source, and the labels and the reading order are pinned
/// as values.
@Suite("Mobile VoiceOver structure")
@MainActor
struct MobileAccessibilityStructureTests {
  private static func source(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
  }

  /// Whether `second` appears in `source` after `first`, within `limit`
  /// characters of it: how a modifier is pinned to the view it follows.
  private static func follows(
    _ second: String, _ first: String, in source: String, within limit: Int = 600
  ) -> Bool {
    guard let start = source.range(of: first) else { return false }
    let tail = source[start.upperBound...].prefix(limit)
    return tail.contains(second)
  }

  private static func task(_ status: LorvexTask.Status, title: String = "Reply to the investor email")
    -> LorvexTask
  {
    LorvexTask(
      id: "task-1", title: title, notes: "", priority: .p2, status: status, dueDate: nil,
      plannedDate: nil, plannedTime: nil, estimatedMinutes: nil, tags: [])
  }

  // MARK: Values

  @Test("a block in a week names its day after its own label; a one-day grid names none")
  func blockLabelNamesTheDayOfAWeekOnly() throws {
    var calendar = Calendar(identifier: .gregorian)
    let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    calendar.timeZone = zone
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
    let day = LorvexDateFormatters.string(date, dateStyle: .full, timeZone: zone)

    #expect(
      MobileCalendarBlockLabel.appendingDay(
        "Standup from 9:00 AM to 9:30 AM", of: date, calendar: calendar)
        == "Standup from 9:00 AM to 9:30 AM, \(day)")
    #expect(
      MobileCalendarBlockLabel.appendingDay("Standup", of: nil, calendar: calendar) == "Standup")
  }

  @Test("blocks read in time order: the earlier a block starts, the higher its sort priority")
  func earlierBlocksReadFirst() {
    let starts = [0, 9 * 60, 9 * 60 + 45, 14 * 60, 24 * 60 - 1]
    let priorities = starts.map { MobileCalendarDayColumn.accessibilitySortPriority(startMin: $0) }
    #expect(priorities == priorities.sorted(by: >))
    #expect(Set(priorities).count == starts.count)
    #expect(priorities.allSatisfy { $0 > 0 })
  }

  @Test("a day is named by its full date, after Today on today only")
  func dayNameSaysTodayOnlyOnToday() throws {
    var calendar = Calendar(identifier: .gregorian)
    let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    calendar.timeZone = zone
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
    let full = LorvexDateFormatters.string(date, dateStyle: .full, timeZone: zone)

    #expect(MobileCalendarDayName.spoken(date, isToday: false, calendar: calendar) == full)
    let today = MobileCalendarDayName.spoken(date, isToday: true, calendar: calendar)
    #expect(today != full)
    #expect(today.hasSuffix(full))
  }

  @Test("the completion circle names its task while the task can be completed")
  func completionCircleNamesItsTask() {
    let title = "Reply to the investor email"
    for status in [LorvexTask.Status.open, .inProgress, .someday] {
      let label = MobileTaskCompletionCircle.spokenLabel(for: Self.task(status, title: title))
      #expect(label.contains(title), "\(status)")
      #expect(label != title)
    }
    // A resolved task's circle is disabled and says the state its glyph shows.
    #expect(
      !MobileTaskCompletionCircle.spokenLabel(for: Self.task(.completed)).contains("investor"))
    #expect(
      !MobileTaskCompletionCircle.spokenLabel(for: Self.task(.cancelled)).contains("investor"))
  }

  @Test("a finished task's check names the task it reopens")
  func reopenCheckNamesItsTask() {
    let title = "Book the dentist appointment"
    let label = MobileTodayDoneRow.reopenLabel(for: Self.task(.completed, title: title))
    #expect(label.contains(title))
    #expect(label.hasPrefix(MobileTodayCalmCopy.reopen))
  }

  // MARK: Structure of the calendar

  @Test("an event block is one element, a button only when it can be opened")
  func eventBlockIsOneElement() throws {
    let block = try Self.source("Sources/LorvexMobile/MobileCalendarEventBlock.swift")
    #expect(Self.follows(".accessibilityLabel(", ".accessibilityElement(children: .ignore)", in: block))
    #expect(block.contains(".accessibilityAddTraits(block.event.editable ? .isButton : [])"))
    #expect(block.contains(".accessibilityAction { if block.event.editable { onTapEvent(block.event) } }"))
    #expect(block.contains(".accessibilitySortPriority(Self.accessibilitySortPriority("))
    let task = try Self.source("Sources/LorvexMobile/MobileCalendarTaskBlock.swift")
    #expect(task.contains(".accessibilitySortPriority(Self.accessibilitySortPriority("))
  }

  @Test("each day column is one container, and the hour labels are not stops")
  func dayColumnGroupsItsBlocksAndHidesTheHourLabels() throws {
    let column = try Self.source("Sources/LorvexMobile/MobileCalendarDayColumn.swift")
    #expect(Self.follows(".accessibilityHidden(true)", "MobileCalendarHourGutter(", in: column, within: 300))
    #expect(column.contains(".accessibilityElement(children: .contain)"))
  }

  @Test("the all-day strip hides empty days and names its pills as single elements")
  func allDayStripStructure() throws {
    let chrome = try Self.source("Sources/LorvexMobile/MobileCalendarDayChrome.swift")
    #expect(
      chrome.contains("let isFree = day.allDayEvents.isEmpty && day.scheduledTasks.isEmpty"))
    #expect(chrome.contains(".mobileCalendarPageReachability(hidden: isFree)"))
    #expect(
      Self.follows(
        ".accessibilityAddTraits(event.editable ? .isButton : [])",
        ".onTapGesture { if event.editable { onTapEvent(event) } }", in: chrome, within: 1500))
  }

  @Test("only the visible week of the week strip pager is reachable by VoiceOver")
  func weekStripPagerHidesTheNeighborWeeks() throws {
    let strip = try Self.source("Sources/LorvexMobile/MobileCalendarWeekStrip.swift")
    #expect(strip.contains(".accessibilityHidden(week != visibleWeek)"))
  }

  @Test("only the visible page of a calendar pager is reachable by VoiceOver")
  func pagersHideTheirNeighborPages() throws {
    // The month pager hides each page as a whole. The day pager cannot: an explicit "not hidden" on
    // a page makes the all-day strip's empty drop-target cells reachable as nameless stops, so the
    // pager only tells each page whether it is the visible one, and the page's headers, all-day
    // label, and time grid hide themselves.
    let month = try Self.source("Sources/LorvexMobile/MobileCalendarMonthView.swift")
    #expect(month.contains(".accessibilityHidden(offset != monthOffset)"))
    let day = try Self.source("Sources/LorvexMobile/MobileCalendarDayView.swift")
    #expect(day.contains(".environment(\\.mobileCalendarPageIsReachable, offset == dayOffset)"))
    #expect(!day.contains(".accessibilityHidden(offset != dayOffset)"))
    let column = try Self.source("Sources/LorvexMobile/MobileCalendarDayColumn.swift")
    #expect(column.components(separatedBy: ".mobileCalendarPageReachability()").count - 1 == 2)
    let chrome = try Self.source("Sources/LorvexMobile/MobileCalendarDayChrome.swift")
    #expect(
      Self.follows(
        ".mobileCalendarPageReachability()",
        ".frame(width: gutterWidth - MobileCalendarHourGutter.labelInset, alignment: .trailing)",
        in: chrome, within: 120))
  }

  @Test("a day's header is one heading: the grid's column header and the agenda's day name")
  func dayHeadersAreOneHeading() throws {
    let chrome = try Self.source("Sources/LorvexMobile/MobileCalendarDayChrome.swift")
    #expect(
      Self.follows(
        ".accessibilityAddTraits(.isHeader)", ".accessibilityElement(children: .ignore)", in: chrome,
        within: 200))
    let agenda = try Self.source("Sources/LorvexMobile/MobileCalendarAgendaPanel.swift")
    #expect(
      Self.follows(
        ".accessibilityAddTraits(.isHeader)", ".accessibilityElement(children: .combine)", in: agenda,
        within: 100))
  }

  // MARK: Other surfaces

  @Test("the notes editor is named, and its placeholder is not a second element")
  func notesEditorIsNamed() throws {
    let editor = try Self.source("Sources/LorvexMobile/MobilePlainTextEditor.swift")
    #expect(editor.contains(".accessibilityLabel(accessibilityLabel ?? placeholder)"))
    #expect(Self.follows(".accessibilityHidden(true)", "Text(placeholder)", in: editor, within: 400))
    let capture = try Self.source("Sources/LorvexMobile/MobileCaptureView.swift")
    #expect(capture.contains("accessibilityLabel: String("))
    #expect(!capture.contains(".accessibilityLabel(\n        String(\n          localized: \"capture.notes.a11y\""))
    let edit = try Self.source("Sources/LorvexMobile/MobileTaskEditSheet.swift")
    #expect(edit.contains(".accessibilityLabel(titleLabel)"))
  }

  @Test("decorative glyphs are not read")
  func decorativeGlyphsAreHidden() throws {
    let moved = try Self.source("Sources/LorvexCore/Support/LorvexReviewMovedList.swift")
    #expect(Self.follows(".accessibilityHidden(true)", "Image(systemName: \"checkmark.circle.fill\")", in: moved, within: 300))
    let habit = try Self.source("Sources/LorvexMobile/MobileHabitDetailPanel.swift")
    #expect(Self.follows(".accessibilityHidden(true)", "Image(systemName: \"sparkles\")", in: habit, within: 200))
  }

  @Test("detail pages mark their titles and their section titles as headings")
  func detailTitlesAreHeadings() throws {
    let titles = [
      ("MobileTaskDetailContent.swift", "Text(userContent: task.title)"),
      ("MobileHabitDetailPanel.swift", "Text(userContent: habit.name)"),
      ("MobileMemoryDetailPanel.swift", "Text(userContent: entry.displayTitle)"),
      ("MobileHabitVisualizationSection.swift", "habits.detail.visualization.title"),
      ("MobileHabitReminderList.swift", "habits.detail.reminders"),
    ]
    for (file, anchor) in titles {
      let source = try Self.source("Sources/LorvexMobile/\(file)")
      #expect(Self.follows(".accessibilityAddTraits(.isHeader)", anchor, in: source, within: 400), "\(file)")
    }
  }

  @Test("the heatmap's element is an overlay of the card, not its far-flung content")
  func heatmapElementHasTheCardsFrame() throws {
    let source = try Self.source("Sources/LorvexMobile/MobileHabitVisualizationSection.swift")
    // The panels above the heatmap hide glyphs of their own, so the pin reads
    // the heatmap panel's code alone.
    let start = try #require(source.range(of: "private struct MobileHabitHeatmapPanel"))
    let panel = String(source[start.lowerBound...])
    #expect(Self.follows(".overlay {", ".accessibilityHidden(true)", in: panel, within: 200))
    #expect(Self.follows(".accessibilityLabel(heatmapAccessibilityLabel)", "Color.clear", in: panel, within: 200))
  }

  @Test("the facts line is static text and the review's section action has a full-size tap target")
  func factsLineAndSectionAction() throws {
    let facts = try Self.source("Sources/LorvexCore/Support/LorvexFactsLine.swift")
    #expect(Self.follows(".accessibilityAddTraits(.isStaticText)", ".accessibilityElement(children: .ignore)", in: facts, within: 100))
    let list = try Self.source("Sources/LorvexCore/Support/LorvexReviewTaskList.swift")
    #expect(list.contains(".padding(.vertical, -Self.actionTapPadding)"))
    #expect(list.contains("actionTapPadding: CGFloat = 13"))
  }

  // MARK: Text sizes

  @Test("the capture preview's first line wraps at the accessibility text sizes")
  func capturePreviewLineWrapsAtAccessibilitySizes() throws {
    let preview = try Self.source("Sources/LorvexMobile/MobileCapturePreview.swift")
    #expect(Self.follows(".lineLimitUnlessAccessibilitySize(1)", "Text(preview.addsLine)", in: preview, within: 200))
  }

  // MARK: Tap targets

  @Test("the circles and the ring reach a 44 pt tap target without moving the layout")
  func circlesAndRingPadTheirTapTarget() throws {
    // A circle that acts pads its label, takes the padding back outside the button, and so keeps
    // the row laid out around the circle's own size.
    let rows = try Self.source("Sources/LorvexMobile/MobileTaskRows.swift")
    let circle = "struct MobileTaskCompletionCircle"
    #expect(Self.follows(".padding(MobileTaskCircleFrame.tapOutset)", circle, in: rows, within: 2500))
    #expect(Self.follows(".padding(-MobileTaskCircleFrame.tapOutset)", circle, in: rows, within: 2500))
    let today = try Self.source("Sources/LorvexMobile/MobileTodayPage.swift")
    let doneRow = "struct MobileTodayDoneRow"
    #expect(Self.follows(".padding(MobileTaskCircleFrame.tapOutset)", doneRow, in: today, within: 2500))
    #expect(Self.follows(".padding(-MobileTaskCircleFrame.tapOutset)", doneRow, in: today, within: 2500))
    let ring = try Self.source("Sources/LorvexMobile/MobileHabitCompletionRing.swift")
    #expect(ring.contains("max(0, (44 - size) / 2)"))
    #expect(Self.follows(".padding(-tapOutset)", ".padding(tapOutset)", in: ring, within: 400))
    // The circle is 26 pt at the default text size; the outset makes it 44 pt across.
    #expect(26 + 2 * MobileTaskCircleFrame.tapOutset >= 44)
  }

  @Test("Add Reminder and the schedule header's menu pad their tap target without moving the layout")
  func smallButtonsPadTheirTapTarget() throws {
    let reminders = try Self.source("Sources/LorvexMobile/MobileHabitReminderList.swift")
    #expect(
      Self.follows(
        ".padding(.vertical, -Self.addTapPadding)", ".padding(.vertical, Self.addTapPadding)",
        in: reminders, within: 300))
    let schedule = try Self.source("Sources/LorvexMobile/MobileTodayScheduleSheet.swift")
    #expect(Self.follows(".padding(-tapOutset)", ".padding(tapOutset)", in: schedule, within: 200))
    #expect(schedule.contains("MobileTodayScheduleMenu(store: store, tapOutset: 12)"))
  }
}
