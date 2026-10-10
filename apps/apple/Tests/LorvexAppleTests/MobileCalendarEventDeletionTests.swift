import LorvexCore
import SwiftUI
import Testing

@testable import LorvexMobile

/// A calendar surface asks one deletion question at a time: the drawing of an
/// event that a row, pill, or block raises is held as pending, which the dialog
/// on that same drawing reads back through the item binding.
@MainActor
@Suite("Calendar event deletion request")
struct MobileCalendarEventDeletionTests {
  /// An optional source with a plain `Binding` over it, the shape of the
  /// surface's `@State` pending request.
  private final class Pending: @unchecked Sendable {
    var request: MobileCalendarEventDeletion.Request?

    var deletion: MobileCalendarEventDeletion {
      MobileCalendarEventDeletion(
        pending: Binding(get: { self.request }, set: { self.request = $0 }),
        deleteEvent: { _ in true }, deleteScoped: { _, _ in true })
    }
  }

  private func event(_ id: String, repeats: Bool = false) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, title: "Standup", source: "lorvex", editable: true, startDate: "2026-10-09",
      startTime: "09:00", endDate: nil, endTime: "09:30", allDay: false, location: nil,
      color: nil, eventType: "event", timezone: nil, isRecurring: repeats)
  }

  @Test("A request holds the event, its day, and its surface as pending")
  func requestHoldsTheDrawing() {
    let pending = Pending()
    pending.deletion.scoped(to: "page-1").request(event("a"), on: "2026-10-09")
    #expect(pending.request?.event.id == "a")
    #expect(pending.request?.dayKey == "2026-10-09")
    #expect(pending.request?.scope == "page-1")
  }

  @Test("A newer request replaces the one before it")
  func newerRequestReplacesTheOlder() {
    let pending = Pending()
    pending.deletion.request(event("a"), on: "2026-10-09")
    pending.deletion.request(event("b"), on: "2026-10-09")
    #expect(pending.request?.event.id == "b")
  }

  @Test("Only the requested occurrence of a repeating event is held")
  func onlyTheRequestedOccurrenceIsHeld() {
    let pending = Pending()
    let first = event("series-2026-10-09", repeats: true)
    let second = event("series-2026-10-16", repeats: true)
    pending.deletion.request(first, on: "2026-10-09")
    #expect(pending.deletion.pending.isHolding(request(first, on: "2026-10-09")).wrappedValue)
    #expect(!pending.deletion.pending.isHolding(request(second, on: "2026-10-16")).wrappedValue)
  }

  @Test("A multi-day event asks only at the day that raised the question")
  func onlyTheRaisingDayAsks() {
    let pending = Pending()
    let trip = event("trip")
    pending.deletion.request(trip, on: "2026-10-10")
    #expect(pending.deletion.pending.isHolding(request(trip, on: "2026-10-10")).wrappedValue)
    #expect(!pending.deletion.pending.isHolding(request(trip, on: "2026-10-11")).wrappedValue)
  }

  @Test("A day drawn on two pages asks only on the page that raised the question")
  func onlyTheRaisingPageAsks() {
    let pending = Pending()
    let standup = event("standup")
    pending.deletion.scoped(to: "2026-10-09").request(standup, on: "2026-10-10")
    #expect(
      pending.deletion.pending.isHolding(request(standup, on: "2026-10-10", scope: "2026-10-09"))
        .wrappedValue)
    #expect(
      !pending.deletion.pending.isHolding(request(standup, on: "2026-10-10", scope: "2026-10-10"))
        .wrappedValue)
  }

  @Test("A surface drawn without a store holds nothing")
  func inertDeletionHoldsNothing() {
    let inert = MobileCalendarEventDeletion.inert
    inert.request(event("a"), on: "2026-10-09")
    #expect(inert.pending.wrappedValue == nil)
  }

  private func request(
    _ event: CalendarTimelineEvent, on dayKey: String, scope: String = ""
  ) -> MobileCalendarEventDeletion.Request {
    MobileCalendarEventDeletion.Request(event: event, scope: scope, dayKey: dayKey)
  }
}
