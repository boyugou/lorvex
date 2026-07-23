#if os(iOS)
import LorvexCore
import LorvexMobile

func makeMobileHomeSnapshot() -> MobileHomeSnapshot {
  MobileHomeSnapshot(
    today: TodaySnapshot(
      focusTitle: "Today",
      summary: "Two active tasks",
      tasks: [
        LorvexTask(
          id: "snap-task-1",
          title: "Write snapshot tests",
          notes: "Cover all major views.",
          priority: .p1,
          status: .open,
          dueDate: nil,
          estimatedMinutes: 30,
          tags: ["dev"]
        )
      ],
      localChangeSequence: 1
    ),
    currentFocus: nil,
    weeklyReview: nil
  )
}

#endif
