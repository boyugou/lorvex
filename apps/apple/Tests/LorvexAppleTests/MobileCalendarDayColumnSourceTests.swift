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

  #expect(source.contains("DateComponents(calendar: calendar)"))
  #expect(source.contains("components.year = 2001"))
  #expect(source.contains("guard let date = calendar.date(from: components)"))
  #expect(!source.contains("calendar.date(from: components) ?? Date()"))
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

  #expect(agenda.contains("let tasks: [LorvexTask]"))
  #expect(agenda.contains("ForEach(day.tasks)"))
  #expect(agenda.contains("MobileCalendarAgendaTaskRow(task: task)"))
  #expect(dayViewAgenda.contains("tasks: tasks"))
  #expect(dayViewAgenda.contains("store.calendarScheduledTasks"))
}
