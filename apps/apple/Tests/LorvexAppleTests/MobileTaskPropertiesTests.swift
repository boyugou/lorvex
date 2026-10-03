import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// Which rows and additions the iPhone task detail lists for a task.
@Suite("iPhone task detail properties")
struct MobileTaskPropertiesTests {
  private static func task(
    planned: String? = nil, due: String? = nil, priority: LorvexTask.Priority = .p2,
    estimate: Int? = nil, tags: [String] = []
  ) -> LorvexTask {
    LorvexTask(
      id: "t", title: "T", notes: "", priority: priority, status: .open,
      dueDate: due.flatMap { LorvexDateFormatters.ymdUTC.date(from: $0) },
      plannedDate: planned.flatMap { LorvexDateFormatters.ymdUTC.date(from: $0) },
      estimatedMinutes: estimate, tags: tags)
  }

  @Test("Set fields are rows in planning order; the rest are additions in the same order")
  func rowsAndAdditions() {
    let properties = MobileTaskProperties(
      task: Self.task(planned: "2026-04-05", due: "2026-04-07", priority: .p1, tags: ["work"]),
      listName: "Inbox", logicalDay: "2026-04-05")
    #expect(properties.rows.map(\.field) == [.doOn, .due, .list, .priority, .tags])
    #expect(properties.additions == [.estimate, .recurrence, .waitsOn, .hideUntil])
    #expect(properties.rows.first { $0.field == .priority }?.tint == .high)
  }

  @Test("A deadline on the planned day names its own day, and an overdue one is tinted")
  func dueNamesItsDay() throws {
    let properties = MobileTaskProperties(
      task: Self.task(planned: "2026-04-04", due: "2026-04-04"), listName: nil,
      logicalDay: "2026-04-05")
    let due = try #require(properties.rows.first { $0.field == .due })
    #expect(due.tint == .overdue)
    #expect(due.value == "Yesterday")
  }

  @Test("A planned day after a deadline still ahead says so and is tinted; shared text keeps only dates")
  func plannedAfterTheDeadline() throws {
    let task = Self.task(planned: "2026-04-06", due: "2026-04-05")
    let properties = MobileTaskProperties(task: task, listName: nil, logicalDay: "2026-04-05")
    let when = try #require(properties.rows.first { $0.field == .doOn })
    #expect(when.value == LorvexDayPhrase.afterDeadline("Tomorrow"))
    #expect(when.tint == .soon)

    let shared = MobileTaskProperties(task: task, listName: nil, logicalDay: "2026-04-05", days: .dated)
    let sharedWhen = try #require(shared.rows.first { $0.field == .doOn })
    #expect(sharedWhen.value == MobileTaskProperties.dated(try #require(task.plannedDate)))
    #expect(sharedWhen.tint == nil)

    // Once the deadline has passed, a later planned day is how the task catches up.
    let overdue = MobileTaskProperties(
      task: Self.task(planned: "2026-04-06", due: "2026-04-04"), listName: nil, logicalDay: "2026-04-05")
    #expect(overdue.rows.first { $0.field == .doOn }?.value == "Tomorrow")
  }

  @Test("The repeat row is the cadence, and tags join into one row")
  func repeatAndTags() {
    let rule = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"], count: 10)
    let task = LorvexTask(
      id: "t", title: "Water the plants", notes: "", priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: ["home", "weekly"], recurrence: rule)
    let properties = MobileTaskProperties(task: task, listName: nil, logicalDay: "2026-09-22")
    #expect(properties.rows.map(\.field) == [.recurrence, .tags])
    #expect(properties.rows.first?.value == rule.localizedCadence)
    #expect(properties.rows.last?.value == "home · weekly")
  }

  @Test("Waits on is offered only while the task waits on nothing")
  func waitsOn() {
    let task = LorvexTask(
      id: "t", title: "Book the venue", notes: "", priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [], dependsOn: ["t1"])
    let properties = MobileTaskProperties(task: task, listName: nil, logicalDay: "2026-09-22")
    #expect(properties.rows.isEmpty)
    #expect(!properties.additions.contains(.waitsOn))
  }

  @Test("A hide-until day that has arrived is offered again instead of listed")
  func hideUntil() {
    func properties(hiddenUntil ymd: String) -> MobileTaskProperties {
      let task = LorvexTask(
        id: "t", title: "Renew the lease", notes: "", priority: .p2, status: .open, dueDate: nil,
        availableFrom: LorvexDateFormatters.ymdUTC.date(from: ymd), estimatedMinutes: nil, tags: [])
      return MobileTaskProperties(task: task, listName: nil, logicalDay: "2026-09-22")
    }
    let hidden = properties(hiddenUntil: "2026-09-25")
    #expect(hidden.rows.map(\.value) == ["Friday"])
    for arrived in ["2026-09-22", "2026-09-20"] {
      #expect(properties(hiddenUntil: arrived).rows.isEmpty)
      #expect(properties(hiddenUntil: arrived).additions.contains(.hideUntil))
    }
  }
}
