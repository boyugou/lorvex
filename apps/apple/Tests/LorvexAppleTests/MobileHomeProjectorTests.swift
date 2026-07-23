import LorvexCore
import LorvexMobile
import Testing

@Test
func mobileHomeProjectorSummarizesFocusAndNextTask() {
  let tasks = [
    makeMobileTask(id: "task-1", title: "First open task", priority: .p2),
    makeMobileTask(id: "task-2", title: "Focused task", priority: .p1),
  ]
  let snapshot = MobileHomeSnapshot(
    today: TodaySnapshot(
      focusTitle: "Today",
      summary: "Two active tasks",
      tasks: tasks,
      localChangeSequence: 12
    ),
    currentFocus: CurrentFocusPlan(
      date: "2026-05-23",
      taskIDs: ["task-2"],
      briefing: "Start with the highest-value task.",
      timezone: "America/Los_Angeles",
      localChangeSequence: 13
    ),
    weeklyReview: WeeklyReviewSnapshot(
      windowTitle: "This Week",
      completedThisWeek: 4,
      createdThisWeek: 5,
      overdueOpen: 1,
      deferredOpen: 2,
      someday: 3,
      estimateCoverageRatio: 0.8,
      topCompleted: [],
      frequentlyDeferred: [],
      topSomeday: []
    )
  )

  let summary = MobileHomeProjector().summary(from: snapshot)

  #expect(summary.focusTitle == "Today")
  #expect(summary.openTaskCount == 2)
  #expect(summary.focusTaskCount == 1)
  #expect(summary.nextTaskTitle == "Focused task")
  #expect(summary.weeklyReviewTitle == "This Week")
  #expect(summary.taskStatusText == "Open tasks: 2, Focus tasks: 1, Next: Focused task")
}

@Test
func mobileHomeSummaryStatusTextHandlesEmptyAndSingularStates() {
  #expect(
    MobileHomeSummary(
      focusTitle: "Today",
      openTaskCount: 0,
      focusTaskCount: 0,
      nextTaskTitle: nil,
      weeklyReviewTitle: nil
    ).taskStatusText == "Open tasks: 0, Focus tasks: 0"
  )
  #expect(
    MobileHomeSummary(
      focusTitle: "Today",
      openTaskCount: 1,
      focusTaskCount: 1,
      nextTaskTitle: "One task",
      weeklyReviewTitle: nil
    ).taskStatusText == "Open tasks: 1, Focus tasks: 1, Next: One task"
  )
}
