import Foundation
import LorvexCore
import Testing

// MARK: - LorvexTaskMarkdownExport

@Test
func taskMarkdownExportContainsTitle() {
  let task = makeTask(title: "Finish release notes")
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(md.contains("# Finish release notes"))
}

@Test
func taskMarkdownExportContainsStatusAndPriority() {
  let task = makeTask(status: .completed, priority: .p1)
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(md.contains("completed"))
  #expect(md.contains("P1"))
}

@Test
func taskMarkdownExportOmitsDueDateWhenNil() {
  let task = makeTask(dueDate: nil)
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(!md.contains("**Due:**"))
}

@Test
func taskMarkdownExportIncludesDueDateWhenPresent() {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let task = makeTask(dueDate: date)
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(md.contains("**Due:**"))
}

@Test
func taskMarkdownExportOmitsNotesWhenEmpty() {
  let task = makeTask(notes: "")
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(!md.contains("## Notes"))
}

@Test
func taskMarkdownExportIncludesNotesWhenPresent() {
  let task = makeTask(notes: "This is an important task.")
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(md.contains("## Notes"))
  #expect(md.contains("This is an important task."))
}

@Test
func taskMarkdownExportRendersChecklist() {
  let items = [
    TaskChecklistItem(id: "c1", taskID: "t1", position: 0, text: "Step one", completedAt: nil),
    TaskChecklistItem(id: "c2", taskID: "t1", position: 1, text: "Step two", completedAt: "2024-01-01"),
  ]
  let task = makeTask(checklistItems: items)
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(md.contains("## Checklist"))
  #expect(md.contains("- [ ] Step one"))
  #expect(md.contains("- [x] Step two"))
}

@Test
func taskMarkdownExportOmitsChecklistWhenEmpty() {
  let task = makeTask(checklistItems: [])
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(!md.contains("## Checklist"))
}

@Test
func taskMarkdownExportIncludesAINotes() {
  let task = makeTask(aiNotes: "AI analysis here.")
  let md = LorvexTaskMarkdownExport.render(task)
  #expect(md.contains("## Assistant Context"))
  #expect(md.contains("AI analysis here."))
}

// MARK: - LorvexDailyReviewMarkdownExport

@Test
func dailyReviewMarkdownContainsDate() {
  let review = makeDailyReview(date: "2024-05-10")
  let md = LorvexDailyReviewMarkdownExport.render(review)
  #expect(md.contains("2024-05-10"))
}

@Test
func dailyReviewMarkdownContainsMoodAndEnergy() {
  let review = makeDailyReview(mood: 4, energy: 3)
  let md = LorvexDailyReviewMarkdownExport.render(review)
  #expect(md.contains("**Mood:** 4/5"))
  #expect(md.contains("**Energy:** 3/5"))
}

@Test
func dailyReviewMarkdownOmitsMoodWhenNil() {
  let review = makeDailyReview(mood: nil, energy: nil)
  let md = LorvexDailyReviewMarkdownExport.render(review)
  #expect(!md.contains("**Mood:**"))
  #expect(!md.contains("**Energy:**"))
}

@Test
func dailyReviewMarkdownIncludesWinsBlockersLearnings() {
  let review = makeDailyReview(
    wins: "Shipped v1.0",
    blockers: "CI is slow",
    learnings: "Use caching"
  )
  let md = LorvexDailyReviewMarkdownExport.render(review)
  #expect(md.contains("## Wins"))
  #expect(md.contains("Shipped v1.0"))
  #expect(md.contains("## Blockers"))
  #expect(md.contains("CI is slow"))
  #expect(md.contains("## Learnings"))
  #expect(md.contains("Use caching"))
}

@Test
func dailyReviewMarkdownOmitsEmptyOptionalSections() {
  let review = makeDailyReview(wins: nil, blockers: nil, learnings: nil)
  let md = LorvexDailyReviewMarkdownExport.render(review)
  #expect(!md.contains("## Wins"))
  #expect(!md.contains("## Blockers"))
  #expect(!md.contains("## Learnings"))
}

// MARK: - LorvexWeeklyReviewMarkdownExport

@Test
func weeklyReviewMarkdownContainsWindowTitle() {
  let snapshot = makeWeeklyReview(windowTitle: "Week of May 6–12, 2024")
  let md = LorvexWeeklyReviewMarkdownExport.render(snapshot)
  #expect(md.contains("Week of May 6–12, 2024"))
}

@Test
func weeklyReviewMarkdownContainsMetrics() {
  let snapshot = makeWeeklyReview(completed: 5, created: 3, overdue: 1, deferred: 2, someday: 4)
  let md = LorvexWeeklyReviewMarkdownExport.render(snapshot)
  #expect(md.contains("| Completed | 5 |"))
  #expect(md.contains("| Created | 3 |"))
  #expect(md.contains("| Overdue | 1 |"))
  #expect(md.contains("| Deferred | 2 |"))
  #expect(md.contains("| Someday | 4 |"))
}

@Test
func weeklyReviewMarkdownIncludesEstimateCoverage() {
  let snapshot = makeWeeklyReview(estimateCoverageRatio: 0.75)
  let md = LorvexWeeklyReviewMarkdownExport.render(snapshot)
  #expect(md.contains("75%"))
}

@Test
func weeklyReviewMarkdownOmitsEstimateCoverageWhenNil() {
  let snapshot = makeWeeklyReview(estimateCoverageRatio: nil)
  let md = LorvexWeeklyReviewMarkdownExport.render(snapshot)
  #expect(!md.contains("Estimate Coverage"))
}

@Test
func weeklyReviewMarkdownIncludesTopCompletedAndDeferred() {
  let completed = [ReviewTaskSummary(id: "t1", title: "Ship it", status: "completed", deferCount: 0)]
  let deferred = [ReviewTaskSummary(id: "t2", title: "Big refactor", status: "deferred", deferCount: 3)]
  let snapshot = makeWeeklyReview(topCompleted: completed, frequentlyDeferred: deferred)
  let md = LorvexWeeklyReviewMarkdownExport.render(snapshot)
  #expect(md.contains("## Completed This Week"))
  #expect(md.contains("Ship it"))
  #expect(md.contains("## Frequently Deferred"))
  #expect(md.contains("Big refactor"))
  #expect(md.contains("3×"))
}

// MARK: - Fixtures

private func makeTask(
  title: String = "Test Task",
  notes: String = "",
  aiNotes: String? = nil,
  status: LorvexTask.Status = .open,
  priority: LorvexTask.Priority = .p2,
  dueDate: Date? = nil,
  checklistItems: [TaskChecklistItem] = []
) -> LorvexTask {
  LorvexTask(
    id: "task-test",
    title: title,
    notes: notes,
    aiNotes: aiNotes,
    priority: priority,
    status: status,
    dueDate: dueDate,
    estimatedMinutes: nil,
    tags: [],
    checklistItems: checklistItems
  )
}

private func makeDailyReview(
  date: String = "2024-01-01",
  summary: String = "A productive day.",
  mood: Int? = nil,
  energy: Int? = nil,
  wins: String? = nil,
  blockers: String? = nil,
  learnings: String? = nil
) -> DailyReviewEntry {
  DailyReviewEntry(
    date: date,
    summary: summary,
    mood: mood,
    energyLevel: energy,
    wins: wins,
    blockers: blockers,
    learnings: learnings,
    timezone: nil,
    updatedAt: nil,
    linkedTaskIDs: [],
    linkedListIDs: []
  )
}

private func makeWeeklyReview(
  windowTitle: String = "This Week",
  completed: Int = 0,
  created: Int = 0,
  overdue: Int = 0,
  deferred: Int = 0,
  someday: Int = 0,
  estimateCoverageRatio: Double? = nil,
  topCompleted: [ReviewTaskSummary] = [],
  frequentlyDeferred: [ReviewTaskSummary] = [],
  topSomeday: [ReviewTaskSummary] = []
) -> WeeklyReviewSnapshot {
  WeeklyReviewSnapshot(
    windowTitle: windowTitle,
    completedThisWeek: completed,
    createdThisWeek: created,
    overdueOpen: overdue,
    deferredOpen: deferred,
    someday: someday,
    estimateCoverageRatio: estimateCoverageRatio,
    topCompleted: topCompleted,
    frequentlyDeferred: frequentlyDeferred,
    topSomeday: topSomeday
  )
}
