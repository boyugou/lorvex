import Foundation
import Testing

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
  #expect(source.contains(".onChanged { _ in userHasScrolledTimeAxis = true }"))
  #expect(source.contains(".onChange(of: startDate) { _, _ in userHasScrolledTimeAxis = false }"))
  #expect(source.contains(".onChange(of: dayCount) { _, _ in userHasScrolledTimeAxis = false }"))
  #expect(source.contains(".onChange(of: scrollSignature)"))
  #expect(source.contains("if !userHasScrolledTimeAxis"))
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
