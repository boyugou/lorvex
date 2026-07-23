#if os(iOS)
import LorvexCore
import LorvexMobile
import SwiftUI
import Testing

@testable import LorvexMobile

@Suite("Mobile calendar view snapshot tests")
@MainActor
struct MobileCalendarViewSnapshotTests {
  @Test
  func mobileCreateCalendarEventSheetRendersDraft() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    store.calendarDraft = MobileCalendarDraft(
      title: "Product Review",
      allDay: true,
      location: "Studio",
      notes: "Bring notes"
    )
    let data = renderSnapshot(
      MobileStoreCreateCalendarEventSheet(store: store, isPresented: .constant(true)),
      size: CGSize(width: 390, height: 650)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileEditCalendarEventSheetRendersDraft() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    let event = CalendarTimelineEvent(
      id: "calendar-edit-snapshot",
      title: "Edit review",
      source: "canonical",
      editable: true,
      startDate: "2026-05-24",
      startTime: nil,
      endDate: nil,
      endTime: nil,
      allDay: true,
      location: "Studio",
      color: "blue",
      eventType: "event",
      timezone: "UTC",
      isRecurring: false
    )
    store.prepareCalendarDraft(for: event)
    let data = renderSnapshot(
      MobileStoreEditCalendarEventSheet(event: event, store: store, isPresented: .constant(true)),
      size: CGSize(width: 390, height: 650)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileCalendarSectionRendersICSExportControl() async {
    let event = CalendarTimelineEvent(
      id: "calendar-export-snapshot",
      title: "Export review",
      source: "canonical",
      editable: true,
      startDate: "2026-05-24",
      startTime: "09:00",
      endDate: nil,
      endTime: "09:30",
      allDay: false,
      location: "Studio",
      color: "blue",
      eventType: "event",
      timezone: "UTC",
      isRecurring: false
    )
    let data = renderSnapshot(
      Form {
        MobileStoreCalendarSection(
          events: [event],
          isMutating: false,
          isExporting: false,
          createEvent: {},
          editEvent: { _ in },
          deleteEvent: { _ in true },
          deleteScopedEvent: { _, _ in true },
          exportICS: { "BEGIN:VCALENDAR\nEND:VCALENDAR" }
        )
      },
      size: CGSize(width: 390, height: 500)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }
}

#endif
