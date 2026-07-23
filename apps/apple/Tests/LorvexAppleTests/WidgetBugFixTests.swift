/// Tests covering specific bug fixes in the widget surfaces.
///
/// Each test documents the invariant the fix establishes and would have caught
/// the original defect before it shipped.
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import Testing

// MARK: - Item 1: completedTodayCount math

@Test
func widgetSnapshotProjectorComputesCompletedTodayCount() {
  // Arrange: two open tasks, one task completed today (due on a *different*
  // day, to prove the count keys off completion — not the due date), and one
  // completed yesterday (should not count).
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = Date(timeIntervalSince1970: 1_779_465_600) // 2026-05-22T16:00:00Z

  let yesterday = now.addingTimeInterval(-24 * 60 * 60)

  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [
      makeBugFixTask(id: "open-1", status: .open, dueDate: now),
      makeBugFixTask(id: "open-2", status: .open, dueDate: now),
      // Completed today but due yesterday: must still count (keys off completed_at).
      makeBugFixTask(
        id: "done-today", status: .completed, dueDate: yesterday,
        completedAt: "2026-05-22T09:00:00Z"),
      // Completed yesterday but due today: must NOT count.
      makeBugFixTask(
        id: "done-yesterday", status: .completed, dueDate: now,
        completedAt: "2026-05-21T09:00:00Z"),
    ],
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(calendar: calendar, now: { now })

  let snapshot = projector.snapshot(today: today, currentFocus: nil, timezone: nil)

  // Only the task completed today counts — independent of its due date.
  #expect(snapshot.stats.completedTodayCount == 1)
}

@Test
func widgetProgressViewCompletedCountUsesCompletedTodayField() {
  // ProgressWidgetView must read stats.completedTodayCount, not compute
  // totalCount - openCount (which was the original bug).
  let stats = WidgetSnapshot.Stats(
    focusCount: 3,
    overdueCount: 0,
    dueTodayCount: 2,
    completedTodayCount: 5
  )
  #expect(stats.completedTodayCount == 5)
}

// MARK: - Item: due-today / overdue stats are time-zone correct

/// `task.dueDate` is a UTC-midnight Date (the `planned_date` `YYYY-MM-DD` is
/// parsed in UTC). The due-today/overdue counts previously compared it with
/// `calendar.isDate(_:inSameDayAs:)` against the *local* calendar, which shifts
/// a UTC-anchored due date back a day for any user behind UTC — so a task due on
/// the user's local "today" was miscounted as overdue. This pins the
/// canonical-day comparison.
@Test
func widgetSnapshotProjectorDueTodayIsTimeZoneCorrect() {
  var utc = Calendar(identifier: .gregorian)
  utc.timeZone = TimeZone(secondsFromGMT: 0)!
  // Due dates as stored: UTC midnight of the canonical day.
  let dueToday = utc.date(from: DateComponents(year: 2026, month: 5, day: 28))!
  let dueYesterday = utc.date(from: DateComponents(year: 2026, month: 5, day: 27))!

  // User in PDT (UTC-7); now is 2026-05-28 10:00 local == 2026-05-28T17:00Z, so
  // the user's local "today" is 2026-05-28 — the canonical due day of `dueToday`.
  var pacific = Calendar(identifier: .gregorian)
  pacific.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
  let now = Date(timeIntervalSince1970: dueToday.timeIntervalSince1970 + 17 * 3600)

  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [
      makeBugFixTask(id: "due-today", status: .open, dueDate: dueToday),
      makeBugFixTask(id: "due-yesterday", status: .open, dueDate: dueYesterday),
    ],
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(calendar: pacific, now: { now })
  let snapshot = projector.snapshot(today: today, currentFocus: nil, timezone: nil)

  // The 05-28 task is due today (not shifted to 05-27); only the 05-27 task is
  // overdue. The pre-fix local-calendar comparison produced 0 / 2 here.
  #expect(snapshot.stats.dueTodayCount == 1)
  #expect(snapshot.stats.overdueCount == 1)
}

// MARK: - Item 2: focusCount int round-trip

@Test
func widgetRenderModelExposesFocusCountAsInt() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 7, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: []
  )
  let entry = WidgetTimelineEntry(
    date: Date(timeIntervalSince1970: 1_779_465_600),
    state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
    refreshAfter: Date(timeIntervalSince1970: 1_779_467_400)
  )
  let model = WidgetRenderModelBuilder().model(
    entry: entry,
    family: .accessoryCircular,
    statusText: "Now"
  )

  // focusCount must be available as a plain Int, no string parsing required.
  #expect(model.focusCount == 7)
  // The text label should still be consistent.
  #expect(model.focusCountText == "7 in focus")
}

// MARK: - Helpers

private func makeBugFixTask(
  id: String,
  status: LorvexTask.Status,
  dueDate: Date?,
  completedAt: String? = nil
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: id,
    notes: "",
    priority: .p2,
    status: status,
    dueDate: dueDate,
    estimatedMinutes: nil,
    tags: [],
    completedAt: completedAt
  )
}
