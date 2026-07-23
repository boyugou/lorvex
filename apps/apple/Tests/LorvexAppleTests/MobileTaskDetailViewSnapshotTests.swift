#if os(iOS)
import LorvexCore
import LorvexMobile
import SwiftUI
import Testing

@testable import LorvexMobile

@Suite("Mobile task detail snapshot tests")
@MainActor
struct MobileTaskDetailViewSnapshotTests {

  @Test
  func mobileTaskDetailContentRendersForTask() {
    let task = LorvexTask(
      id: "snap-task-detail",
      title: "Mobile task detail snapshot",
      notes: "Verify detail renders correctly.",
      aiNotes: "AI-generated context for mobile review.",
      priority: .p2,
      status: .open,
      dueDate: Date(timeIntervalSince1970: 1_779_494_400),
      estimatedMinutes: 45,
      tags: ["mobile"],
      dependsOn: ["snap-dependency"],
      latenessState: "on-track"
    )
    let data = renderSnapshot(
      MobileTaskDetailContent(task: task), size: CGSize(width: 390, height: 844))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileTaskDetailContentRendersRecurrence() {
    let task = LorvexTask(
      id: "snap-task-recurring",
      title: "Mobile recurring detail snapshot",
      notes: "",
      priority: .p1,
      status: .open,
      dueDate: nil,
      estimatedMinutes: 30,
      tags: [],
      recurrence: TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "WE"]),
      recurrenceExceptions: ["2026-06-01"]
    )
    let data = renderSnapshot(
      MobileTaskDetailContent(task: task), size: CGSize(width: 390, height: 844))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileTaskDetailContentRendersChecklist() {
    let task = LorvexTask(
      id: "snap-task-checklist",
      title: "Mobile checklist detail snapshot",
      notes: "",
      priority: .p1,
      status: .open,
      dueDate: nil,
      estimatedMinutes: 30,
      tags: [],
      checklistItems: [
        TaskChecklistItem(
          id: "snap-item-1",
          taskID: "snap-task-checklist",
          position: 0,
          text: "Verify unchecked item",
          completedAt: nil
        ),
        TaskChecklistItem(
          id: "snap-item-2",
          taskID: "snap-task-checklist",
          position: 1,
          text: "Verify completed item",
          completedAt: "2026-05-24T12:00:00Z"
        ),
      ]
    )
    let data = renderSnapshot(
      MobileTaskDetailContent(task: task), size: CGSize(width: 390, height: 844))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileTaskDetailContentRendersReminders() {
    let task = LorvexTask(
      id: "snap-task-reminders",
      title: "Mobile reminder detail snapshot",
      notes: "",
      priority: .p1,
      status: .open,
      dueDate: nil,
      estimatedMinutes: 30,
      tags: [],
      reminders: [
        TaskReminder(
          id: "snap-reminder-1",
          reminderAt: "2026-05-24T12:00:00Z",
          status: "pending"
        )
      ]
    )
    let data = renderSnapshot(
      MobileTaskDetailContent(task: task), size: CGSize(width: 390, height: 844))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

}

#endif
