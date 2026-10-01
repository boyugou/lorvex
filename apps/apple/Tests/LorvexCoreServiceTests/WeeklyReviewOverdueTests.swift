import Foundation
import Testing

@testable import LorvexCore

/// The week review lists the tasks its sentence counts as overdue, so the user
/// can open each one and decide instead of only reading a number.
@Suite("Week review overdue tasks")
struct WeeklyReviewOverdueTests {
  @Test("the snapshot carries overdue tasks with their due day, earliest first")
  func snapshotListsOverdueTasks() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    func task(_ title: String, due: String) async throws -> LorvexTask {
      let created = try await service.createTask(title: title, notes: "")
      return try await service.updateTask(
        id: created.id, title: title, notes: "", priority: created.priority,
        estimatedMinutes: nil, dueDate: LorvexDateFormatters.ymdUTC.date(from: due),
        plannedDate: nil, availableFrom: nil, tags: [], dependsOn: [])
    }
    let later = try await task("Renew passport", due: "2020-03-02")
    let earlier = try await task("File taxes", due: "2020-01-15")
    _ = try await task("Plan the trip", due: "2099-01-15")

    let review = try await service.loadWeeklyReview()

    #expect(review.overdueOpen == 2)
    #expect(review.overdueTasks.map(\.id) == [earlier.id, later.id])
    #expect(review.overdueTasks.map(\.dueDate) == ["2020-01-15", "2020-03-02"])
  }

  @Test("each task appears once: the decision, then overdue, then pushed")
  func sectionsShowEachTaskOnce() {
    func summary(_ id: String, deferCount: Int = 0) -> ReviewTaskSummary {
      ReviewTaskSummary(id: id, title: id, status: "open", deferCount: deferCount)
    }
    let review = WeeklyReviewSnapshot(
      windowTitle: "", completedThisWeek: 0, createdThisWeek: 0, overdueOpen: 3,
      deferredOpen: 3, someday: 0, estimateCoverageRatio: nil, topCompleted: [],
      frequentlyDeferred: [
        summary("decide", deferCount: 6), summary("late-and-pushed", deferCount: 4),
        summary("pushed", deferCount: 3),
      ],
      overdueTasks: [summary("decide"), summary("late-and-pushed"), summary("late")],
      topSomeday: [])

    #expect(
      LorvexWeekReviewSentence.pastDue(review, decisionID: "decide").map(\.id)
        == ["late-and-pushed", "late"])
    #expect(LorvexWeekReviewSentence.otherPushed(review, decisionID: "decide").map(\.id) == ["pushed"])
    #expect(LorvexWeekReviewSentence.pastDue(review, decisionID: nil).count == 3)
  }

  @Test("how long ago a task was due counts whole days in the user's calendar")
  func dueAgoCountsLocalDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    // 23:30 on Monday 2026-09-28 in Los Angeles is already Tuesday in UTC.
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-29T06:30:00Z"))
    let relative = LorvexDateFormatters.namedRelative

    #expect(
      LorvexWeekReviewSentence.dueAgo(dayKey: "2026-09-27", now: now, calendar: calendar)
        == relative.localizedString(from: DateComponents(day: -1)))
    #expect(
      LorvexWeekReviewSentence.dueAgo(dayKey: "2026-09-25", now: now, calendar: calendar)
        == "3 days ago")
    #expect(LorvexWeekReviewSentence.dueAgo(dayKey: "Friday", now: now, calendar: calendar) == nil)
  }
}
