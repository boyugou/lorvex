import Foundation
import LorvexCore
import Testing

/// The text a task is shared or copied as, with fixed labels so the layout is
/// checked apart from any surface's catalog.
@Suite("Task share text")
struct LorvexTaskShareTextTests {
  private static let labels = LorvexTaskShareLabels(
    field: { field in
      switch field {
      case .doOn: "When"
      case .estimate: "How long"
      case .due: "Due"
      case .list: "List"
      case .priority: "Priority"
      case .recurrence: "Repeat"
      case .tags: "Tags"
      case .hideUntil: "Hide until"
      }
    },
    line: { "\($0): \($1)" },
    dayAtTime: { day, range in "\(day) at \(range.lowerBound)-\(range.upperBound)" },
    assistantContext: "Assistant Context",
    checklist: "Checklist")

  private static func day(_ key: String) -> Date? {
    LorvexDateFormatters.ymdUTC.date(from: key)
  }

  private static func text(_ task: LorvexTask, listName: String? = nil, logicalDay: String = "2026-09-28") -> String {
    LorvexTaskShareText.text(for: task, listName: listName, logicalDay: logicalDay, labels: labels)
  }

  @Test("A task shares its status, notes, fields as dates, assistant context, and checklist in order")
  func shareTextOfAFullTask() {
    let task = LorvexTask(
      id: "t", title: "Ship the release", notes: "Coordinate with QA.",
      aiNotes: "Blocked on review last week.", priority: .p1, status: .inProgress,
      dueDate: Self.day("2026-09-29"), plannedDate: Self.day("2026-09-28"), estimatedMinutes: 45,
      tags: ["work", "release"],
      checklistItems: [
        TaskChecklistItem(id: "c2", taskID: "t", position: 1, text: "Ask QA", completedAt: nil),
        TaskChecklistItem(id: "c1", taskID: "t", position: 0, text: "Draft notes", completedAt: "2026-09-27"),
      ])
    #expect(
      Self.text(task, listName: "Work") == """
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

  @Test("An open task with nothing set, blank notes, and normal priority shares its title alone")
  func shareTextOfABareTask() {
    let task = LorvexTask(
      id: "t", title: "Water the plants", notes: "  \n", aiNotes: " ", priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [])
    #expect(Self.text(task) == "Water the plants")
  }

  @Test("A planned time follows its day, worded by the surface")
  func shareTextPlannedTime() {
    let task = LorvexTask(
      id: "t", title: "Call", notes: "", priority: .p2, status: .open, dueDate: nil,
      plannedDate: Self.day("2026-09-28"), plannedTime: 570..<630, estimatedMinutes: nil, tags: [])
    #expect(Self.text(task) == "Call\n\nWhen: Mon, Sep 28, 2026 at 570-630")
  }

  @Test("A planned day after a deadline that is still ahead is shared as its date alone")
  func shareTextKeepsOnlyDates() {
    let task = LorvexTask(
      id: "t", title: "Pay rent", notes: "", priority: .p2, status: .open,
      dueDate: Self.day("2026-09-29"), plannedDate: Self.day("2026-09-30"), estimatedMinutes: nil, tags: [])
    #expect(Self.text(task) == "Pay rent\n\nWhen: Wed, Sep 30, 2026\nDue: Tue, Sep 29, 2026")
  }

  @Test("A hide-until day is shared while it is ahead and left out once it has arrived")
  func shareTextHideUntil() {
    let ahead = LorvexTask(
      id: "t", title: "Renew", notes: "", priority: .p2, status: .open, dueDate: nil,
      availableFrom: Self.day("2026-10-05"), estimatedMinutes: nil, tags: [])
    #expect(Self.text(ahead) == "Renew\n\nHide until: Mon, Oct 5, 2026")

    let arrived = LorvexTask(
      id: "t", title: "Renew", notes: "", priority: .p2, status: .open, dueDate: nil,
      availableFrom: Self.day("2026-09-20"), estimatedMinutes: nil, tags: [])
    #expect(Self.text(arrived) == "Renew")
  }
}
