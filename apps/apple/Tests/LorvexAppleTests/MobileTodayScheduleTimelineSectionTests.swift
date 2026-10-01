import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// Which timeline rows the mobile schedule list draws: rows the clock has
/// cleared only once unfolded.
@Test
func mobileTimelineSectionFoldsPastRows() {
  let items = [
    LorvexTodayTimelineItem(
      id: "event:standup", kind: .event(standup), startMinutes: 9 * 60, isPast: true),
    LorvexTodayTimelineItem(id: "now", kind: .now, startMinutes: 10 * 60),
    LorvexTodayTimelineItem(id: "task:a", kind: .task(task("a")), startMinutes: 11 * 60),
  ]

  #expect(
    MobileTodayScheduleTimelineSection.visibleItems(of: items, showsPast: false).map(\.id)
      == ["now", "task:a"])
  #expect(
    MobileTodayScheduleTimelineSection.visibleItems(of: items, showsPast: true).map(\.id)
      == ["event:standup", "now", "task:a"])
}

/// A finished meeting after a task still to do stays where it is: folding it
/// behind a line drawn above that task would put it out of the day's order.
@Test
func mobileTimelineSectionKeepsALaterPastRowInPlace() {
  let items = [
    LorvexTodayTimelineItem(id: "task:a", kind: .task(task("a")), startMinutes: 8 * 60),
    LorvexTodayTimelineItem(
      id: "event:standup", kind: .event(standup), startMinutes: 9 * 60, isPast: true),
    LorvexTodayTimelineItem(id: "now", kind: .now, startMinutes: 10 * 60),
  ]

  #expect(
    MobileTodayScheduleTimelineSection.visibleItems(of: items, showsPast: false).map(\.id)
      == ["task:a", "event:standup", "now"])
}

/// What VoiceOver says after a task row's time and title: what its circle,
/// tint, and quiet title show. A finished task is only finished, whatever
/// else is true of it.
@Test
func mobileTimelineSectionSpeaksATaskRowsState() {
  func state(done: Bool = false, now: Bool = false, blocked: Bool = false) -> String {
    MobileTodayScheduleTimelineSection.accessibilityState(isDone: done, isCurrent: now, isBlocked: blocked)
  }
  #expect(state(done: true, blocked: true) == "Completed")
  #expect(state(now: true) == "Now")
  #expect(state(now: true, blocked: true) == "Now, Blocked")
  #expect(state(blocked: true) == "Blocked")
  #expect(state() == "")
}

private let standup = CalendarTimelineEvent(
  id: "standup", eventID: "standup", supportsScopedMutation: false, title: "Standup",
  source: "canonical", editable: true, startDate: "2026-05-23", startTime: "09:00",
  endDate: "2026-05-23", endTime: "09:15", allDay: false, location: nil, color: nil,
  eventType: "event", timezone: nil, isRecurring: false)

private func task(_ id: String) -> LorvexTask {
  LorvexTask(
    id: id, title: id, notes: "", priority: .p2, status: .open, dueDate: nil,
    estimatedMinutes: nil, tags: [])
}
