import Foundation
import LorvexCore
import SwiftUI
import Testing

@testable import LorvexMobile

/// A calendar event that a device calendar owns opens a read-only detail on the
/// iPhone and iPad, and an event Lorvex owns opens its editor. Before the
/// detail existed, Today opened the editor for a mirrored event too, with a
/// Save that did nothing, and the calendar grids and the agenda gave it no tap
/// at all.
@MainActor
@Suite("Mobile calendar event detail")
struct MobileCalendarEventDetailTests {
  private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: "Sources/LorvexMobile/\(path)"), encoding: .utf8)
  }

  private func renderedSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return renderer.nsImage?.size ?? .zero
  }

  private func event(
    location: String? = nil, notes: String? = nil, url: String? = nil,
    attendees: [CalendarEventAttendee]? = nil
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: "e", title: "Team sync", source: "provider", editable: false, startDate: "2026-10-02",
      startTime: "09:00", endDate: "2026-10-02", endTime: "10:30", allDay: false,
      location: location, notes: notes, url: url, color: nil, eventType: "event",
      attendees: attendees, timezone: nil, isRecurring: false)
  }

  @Test("The share text is the shared layout, in this app's words")
  func shareText() {
    let time = lorvexClockRangeLabel(start: "09:00", end: "10:30")
    let full = event(
      location: "Studio", notes: "Bring the roadmap.", url: "https://example.com/room",
      attendees: [CalendarEventAttendee(email: "sam@example.com", name: "Sam")])
    #expect(
      MobileShareText.event(full)
        == """
        Team sync

        When: Friday, October 2, \(time)
        Location: Studio
        Attendees: Sam
        URL: https://example.com/room

        Bring the roadmap.
        """)
    #expect(MobileShareText.event(event()) == "Team sync\n\nWhen: Friday, October 2, \(time)")
  }

  @Test("Every surface that lists events presents the one sheet that picks the detail or the editor")
  func everyEventSurfacePresentsTheSharedSheet() throws {
    for file in [
      "MobileCalendarDayView.swift", "MobileCalendarMonthView.swift",
      "MobileCalendarSearchResults.swift", "MobileStoreTodayView.swift",
    ] {
      let text = try source(file)
      #expect(text.contains("MobileStoreCalendarEventSheet("), "\(file) presents the shared sheet")
      #expect(!text.contains("MobileStoreEditCalendarEventSheet("), "\(file) never opens the editor directly")
    }
    #expect(try source("MobileCalendarEventDetailSheet.swift").contains("event.appleCalendarURL"))
    let sheet = try source("MobileStoreCalendarEventSheet.swift")
    #expect(sheet.contains("if event.editable {"))
    #expect(sheet.contains("MobileStoreEditCalendarEventSheet("))
    #expect(sheet.contains("MobileCalendarEventDetailSheet("))
  }

  @Test("A mirrored event answers a tap on the grids and in the agenda instead of ignoring it")
  func mirroredEventsAnswerATap() throws {
    for (file, ignoredTap) in [
      ("MobileCalendarEventBlock.swift", "if block.event.editable { onTapEvent(block.event) }"),
      ("MobileCalendarDayChrome.swift", "if event.editable { onTapEvent(event) }"),
      ("MobileCalendarMonthDayCell.swift", "where event.editable: openEvent(event)"),
      ("MobileCalendarAgendaPanel.swift", ".disabled(!event.editable)"),
    ] {
      #expect(!(try source(file)).contains(ignoredTap), "\(file) no longer ignores a mirrored event's tap")
    }
  }

  @Test("The detail grows taller, never wider, in a width narrower than its rows")
  func detailWrapsInsideItsWidth() {
    let content = MobileCalendarEventDetailContent(
      event: event(
        location: "The studio on the second floor of the old warehouse",
        notes: "Bring the roadmap and the latest numbers.",
        attendees: [
          CalendarEventAttendee(email: "sam@example.com", name: "Sam Rivera"),
          CalendarEventAttendee(email: "lee@example.com"),
        ]))
    let roomy = renderedSize(content, width: 600)
    let narrow = renderedSize(content, width: 170)

    #expect(roomy.width > 170)
    #expect(narrow.width <= 170, "the detail is \(narrow.width) pt wide in 170 pt")
    #expect(narrow.height > roomy.height)
  }
}
