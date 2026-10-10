import CoreGraphics
import Foundation
import Testing
@testable import LorvexMobile

@Test
func mobileCalendarDayColumnDoesNotReanchorAfterUserScrollsTimeAxis() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "Sources/LorvexMobile/MobileCalendarDayColumn.swift")
  let source = try String(contentsOf: root, encoding: .utf8)

  #expect(source.contains("let scrollSignature = scrollAnchorSignature"))
  #expect(source.contains("@State private var userHasScrolledTimeAxis = false"))
  #expect(source.contains("if phase == .interacting { userHasScrolledTimeAxis = true }"))
  #expect(source.contains(".onChange(of: startDate) { _, _ in userHasScrolledTimeAxis = false }"))
  #expect(source.contains(".onChange(of: dayCount) { _, _ in userHasScrolledTimeAxis = false }"))
  #expect(source.contains(".onChange(of: scrollSignature)"))
  #expect(source.contains("if !userHasScrolledTimeAxis"))
}

@Test
func mobileCalendarGridLeavesSidewaysSwipesToTheDayPager() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  func source(_ name: String) throws -> String {
    try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/\(name).swift"), encoding: .utf8)
  }
  let column = try source("MobileCalendarDayColumn")
  let eventBlock = try source("MobileCalendarEventBlock")
  let taskBlock = try source("MobileCalendarTaskBlock")
  let lift = try source("MobileCalendarEventLift")

  // A SwiftUI drag-type gesture that is able to begin on a view takes every
  // touch that lands on it, so a swipe across the time grid or a block never
  // reached the pager that turns the day or week. Nothing the grid draws
  // carries one: the grid reads its scroll position from the scroll phase, and
  // an event block lifts through a UIKit long press, which fails when the
  // finger moves early and so leaves a swipe to the pager.
  for text in [column, eventBlock, taskBlock] {
    #expect(!text.contains("DragGesture"))
    #expect(!text.contains("LongPressGesture"))
    #expect(!text.contains("simultaneousGesture"))
  }
  #expect(column.contains(".onScrollPhaseChange"))
  #expect(eventBlock.contains(".lorvexEventLift("))
  #expect(lift.contains("UILongPressGestureRecognizer()"))
  #expect(lift.contains("recognizer.allowableMovement = Self.allowableMovement"))
  // A context menu on the same view holds back the lift's press, so a block
  // that lifts shows its menu items empty and offers Delete as a VoiceOver
  // action instead.
  #expect(eventBlock.contains("if block.event.editable && !isReschedulable {"))
  #expect(eventBlock.contains("if block.event.editable && isReschedulable { deleteButton("))
}

@Test
func mobileCalendarBlocksAreLaidOutWhereTheyDrawSoTheirMenusAndDialogsAnchorAtThem() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  func source(_ name: String) throws -> String {
    try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/\(name).swift"), encoding: .utf8)
  }
  let eventBlock = try source("MobileCalendarEventBlock")
  let taskBlock = try source("MobileCalendarTaskBlock")

  // The system anchors a context menu's lifted preview and a dialog's popover
  // at a view's laid-out frame, which an offset does not move: a block placed
  // by `.offset` opened both at the top-left corner of its day column. A block
  // takes its place from alignment guides, and the only offset left is the
  // travel of a lifted event block.
  for text in [eventBlock, taskBlock] {
    #expect(text.contains(".alignmentGuide(.leading) { _ in -x }"))
    #expect(text.contains(".alignmentGuide(.top) { _ in -y }"))
  }
  #expect(eventBlock.contains(".offset(x: dragOffsetX, y: dragOffsetY)"))
  #expect(!eventBlock.contains(".offset(x: CGFloat(block.lane)"))
  #expect(!taskBlock.contains(".offset("))
}

@Test
func mobileCalendarPagerHandsEachPageTheDeletionQuestionOpenOnIt() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let day = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayView.swift"),
    encoding: .utf8)

  // A page whose inputs are unchanged is not evaluated again, so a dialog
  // inside its column learns of a question only through the page's inputs.
  #expect(
    day.contains("openDeletion: eventPendingDeletion.flatMap { $0.scope == scope ? $0.id : nil }"))
  #expect(day.contains("scope: pageScope(startingOn: startDate)"))
}

@Test
func mobileCalendarAgendaEventRowTakesATapAcrossItsWholeWidth() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarAgendaRow.swift"),
    encoding: .utf8)
  let start = try #require(source.range(of: "struct MobileCalendarAgendaRow: View"))
  let end = try #require(source.range(of: "struct MobileCalendarAgendaTaskRow: View"))

  // The row is the label of a plain button, which takes touches only on its
  // label's drawn content and a short way around it; without a content shape
  // a tap on the empty middle or right of a row with a short title did
  // nothing.
  #expect(source[start.lowerBound..<end.lowerBound].contains(".contentShape(Rectangle())"))
}

@Test
func mobileCalendarDayColumnIncludesScheduledTasksInAllDayStrip() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let column = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayColumn.swift"),
    encoding: .utf8
  )
  let chrome = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayChrome.swift"),
    encoding: .utf8
  )

  #expect(column.contains("let tasks: [LorvexTask]"))
  #expect(column.contains("tasks: tasks"))
  #expect(chrome.contains("!$0.scheduledTasks.isEmpty"))
  #expect(chrome.contains("ForEach(day.scheduledTasks)"))
}

@Test
func mobileCalendarDayHourLabelsDoNotFallbackToDateNow() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayChrome.swift"),
    encoding: .utf8
  )
  let formatters = try String(
    contentsOf: root.appending(path: "Sources/LorvexCore/Support/LorvexDateFormatters.swift"),
    encoding: .utf8
  )

  // The gutter reads the shared hour labels, which build each hour's date from
  // components and name the bare hour when that fails, never the current time.
  #expect(source.contains("LorvexDateFormatters.hourLabels(timeZone: calendar.timeZone)"))
  #expect(formatters.contains("else { return \"\\(hour)\" }"))
  #expect(!formatters.contains("?? Date()"))
}

@Test
func mobileCalendarAllDayLabelSitsInsideTheGutterWidth() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayChrome.swift"),
    encoding: .utf8
  )

  // The label is framed as the hour labels are, inside a cell as wide as the
  // gutter, so it ends where they end and the strip's day columns start where
  // the header's and the grid's do. Padding added after a gutter-wide frame
  // would push every all-day pill right of the column it belongs to.
  let label = try #require(
    source.range(of: ".frame(width: gutterWidth - MobileCalendarHourGutter.labelInset, alignment: .trailing)"))
  #expect(source[label.upperBound...].prefix(40).contains(".frame(width: gutterWidth)"))
  #expect(!source.contains(".padding(.trailing, 6)"))
  // The gutter is wide enough for the label's widest word, which wrapping cannot break.
  #expect(
    source.contains("MobileCalendarAllDayStrip.label.split(whereSeparator: \\.isWhitespace)"))
}

@Test
func mobileCalendarAgendaPanelIncludesScheduledTasks() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let agenda = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarAgendaPanel.swift"),
    encoding: .utf8
  )
  let dayViewAgenda = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayView+Agenda.swift"),
    encoding: .utf8
  )
  let agendaDay = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarAgendaDay.swift"),
    encoding: .utf8
  )

  #expect(agendaDay.contains("let tasks: [LorvexTask]"))
  #expect(agenda.contains("ForEach(day.entries)"))
  #expect(agendaDay.contains("case task(LorvexTask)"))
  #expect(agenda.contains("MobileCalendarAgendaTaskRow("))
  // A row reads its time on the day it was grouped under, never a key formatted
  // in another time zone.
  #expect(agenda.contains("task: task, dayKey: day.key,"))
  #expect(agendaDay.contains("CalendarGridModel.scheduledTaskDayKey(task) == key"))
  #expect(
    agendaDay.contains(
      "date: date, key: key, events: agendaEvents(from: events, on: key), tasks: dayTasks"))
  #expect(dayViewAgenda.contains("MobileCalendarAgendaDay.days("))
  #expect(dayViewAgenda.contains("store.calendarScheduledTasks"))
}

@Test
func mobileCalendarDayColumnBuildsNoViewPerHourAndNoSecondPass() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayColumn.swift"),
    encoding: .utf8
  )

  // The hour lines are one shape and one tap gesture per day column; a view
  // and a gesture per hour made every seven-day page build 168 of them while
  // the pager laid it out ahead of the swipe, and a Canvas stalled the first
  // swipe that brought its page in.
  #expect(source.contains("MobileHourLinesShape(hourHeight:"))
  #expect(!source.contains("Canvas {"))
  #expect(!source.contains("ForEach(0..<24"))
  // The pager hands the column its width, so a page is drawn once when it is
  // built; a width the column measured and stored in its own state would
  // draw every new page a second time.
  #expect(source.contains("var pageWidth: CGFloat = 0"))
  #expect(!source.contains("@State private var pageWidth"))
  #expect(!source.contains("onGeometryChange"))
}

@MainActor
@Test
func mobileCalendarDayColumnMapsATapToTheHourUnderIt() {
  let hourHeight: CGFloat = 56
  let cases: [(y: CGFloat, hour: Int)] = [
    (-3, 0), (0, 0), (55.9, 0), (56, 1), (673, 12), (1343.5, 23), (1344, 23), (5000, 23),
  ]
  for (y, hour) in cases {
    #expect(MobileCalendarDayColumn.hour(atY: y, hourHeight: hourHeight) == hour)
  }
}
