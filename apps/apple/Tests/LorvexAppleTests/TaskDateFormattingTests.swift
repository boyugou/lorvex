import Foundation
import LorvexCore
import Testing

@Test
func taskDueDateDisplaySummaryFormatsDateOnly() {
  let task = LorvexTask(
    id: "task-date-format",
    title: "Format date",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: Date(timeIntervalSince1970: 1_779_494_400),
    estimatedMinutes: nil,
    tags: []
  )

  #expect(task.dueDateDisplaySummary?.contains("2026") == true)
}

@Test
func taskDueDateDisplaySummaryIsNilWithoutDueDate() {
  let task = LorvexTask(
    id: "task-no-date",
    title: "No date",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: []
  )

  #expect(task.dueDateDisplaySummary == nil)
}
