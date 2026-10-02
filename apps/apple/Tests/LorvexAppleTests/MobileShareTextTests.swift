import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// What the iPhone share sheet sends for a task and for the day and week
/// reviews: the screen's words in plain lines, with dates that stay true.
@Suite("iPhone share text")
struct MobileShareTextTests {
  private static func day(_ key: String) -> Date? {
    LorvexDateFormatters.ymdUTC.date(from: key)
  }

  @Test("A task shares its status, notes, fields as dates, assistant context, and checklist")
  func taskText() {
    let task = LorvexTask(
      id: "t", title: "Ship the release", notes: "Coordinate with QA.",
      aiNotes: "Blocked on review last week.", priority: .p1, status: .inProgress,
      dueDate: Self.day("2026-09-29"), plannedDate: Self.day("2026-09-28"), estimatedMinutes: 45,
      tags: ["work", "release"],
      checklistItems: [
        TaskChecklistItem(id: "c2", taskID: "t", position: 1, text: "Ask QA", completedAt: nil),
        TaskChecklistItem(id: "c1", taskID: "t", position: 0, text: "Draft notes", completedAt: "2026-09-27"),
      ])
    let text = MobileShareText.task(task, listName: "Work", logicalDay: "2026-09-28")
    #expect(
      text == """
        Ship the release
        In Progress

        Coordinate with QA.

        When: Mon, Sep 28, 2026
        How long: 45 min
        Due: Tue, Sep 29, 2026
        List: Work
        Priority: High
        Tags: work · release

        Assistant Context
        Blocked on review last week.

        Checklist
        - [x] Draft notes
        - [ ] Ask QA
        """)
  }

  @Test("An open task with nothing set shares its title alone")
  func bareTaskText() {
    let task = LorvexTask(
      id: "t", title: "Water the plants", notes: "  \n", priority: .p2, status: .open, dueDate: nil,
      estimatedMinutes: nil, tags: [])
    #expect(MobileShareText.task(task, listName: nil, logicalDay: "2026-09-28") == "Water the plants")
  }

  @Test("A day review shares its date, feeling and energy, and what was written")
  func dailyReviewText() {
    let review = DailyReviewEntry(
      date: "2026-09-28", summary: "A productive day.", mood: 4, energyLevel: 3,
      wins: "Shipped v1.0", blockers: " ", learnings: "Use caching", timezone: nil, updatedAt: nil,
      linkedTaskIDs: [], linkedListIDs: [])
    #expect(
      MobileShareText.dailyReview(review) == """
        Daily Review — Monday, September 28, 2026

        Feeling 4 of 5 · Energy 3 of 5

        Note
        A productive day.

        Wins
        Shipped v1.0

        Learnings
        Use caching
        """)
  }

  @Test("A week review lists each task once, under the first section that names it")
  func weeklyReviewText() {
    let overdue = ReviewTaskSummary(
      id: "o", title: "File taxes", status: "open", deferCount: 4, dueDate: "2026-09-24")
    let review = WeeklyReviewSnapshot(
      windowTitle: "2026-09-22 - 2026-09-28", completedThisWeek: 5, createdThisWeek: 3,
      overdueOpen: 1, deferredOpen: 2, someday: 0, estimateCoverageRatio: nil,
      topCompleted: [ReviewTaskSummary(id: "c", title: "Ship it", status: "completed", deferCount: 0)],
      frequentlyDeferred: [
        overdue, ReviewTaskSummary(id: "p", title: "Big refactor", status: "open", deferCount: 3),
      ],
      overdueTasks: [overdue], topSomeday: [])
    let blocks = MobileShareText.weeklyReview(review).components(separatedBy: "\n\n")
    #expect(blocks.count == 5)
    #expect(blocks[0].hasPrefix("Weekly Review — September 22"))
    #expect(blocks[0].hasSuffix("2026"))
    #expect(blocks[1] == MobileReviewCalmCopy.weekSentence(LorvexWeekReviewSentence.parts(review)))
    #expect(blocks[2] == "What moved forward\n- Ship it")
    #expect(blocks[3] == "Overdue\n- File taxes")
    #expect(blocks[4] == "Kept getting pushed\n- Big refactor (Pushed 3 times)")
  }

  @Test("A week with Someday ideas ends on that line")
  func weeklyReviewSomeday() {
    let review = WeeklyReviewSnapshot(
      windowTitle: "2026-09-22 - 2026-09-28", completedThisWeek: 0, createdThisWeek: 0,
      overdueOpen: 0, deferredOpen: 0, someday: 12, estimateCoverageRatio: nil, topCompleted: [],
      frequentlyDeferred: [], topSomeday: [])
    let blocks = MobileShareText.weeklyReview(review).components(separatedBy: "\n\n")
    #expect(blocks.count == 3)
    #expect(blocks[2] == "12 ideas wait in Someday.")
  }
}
