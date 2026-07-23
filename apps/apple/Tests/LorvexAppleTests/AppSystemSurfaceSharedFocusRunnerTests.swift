import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerMutatesFocusStateAndSchedule() async throws {
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try await core.getSessionContext().date
  let task = try await core.createTask(title: "Shared system focus task", notes: "")
  let focusedCount = try await LorvexSystemIntentRunner.addTaskToFocus(
    id: task.id, core: core)
  #expect(focusedCount == 1)
  let focus = try #require(try await core.loadCurrentFocus(date: logicalDay))
  #expect(focus.taskIDs == [task.id])
  let readFocus = try #require(
    try await LorvexSystemIntentRunner.readCurrentFocus(
      date: nil, core: core))
  #expect(readFocus.date == logicalDay)
  #expect(readFocus.taskIDs == [task.id])
  let removedFocus = try await LorvexSystemIntentRunner.removeTaskFromFocus(
    id: " \(task.id) ", date: nil, core: core)
  #expect(removedFocus == nil)
  #expect(try await core.loadCurrentFocus(date: logicalDay) == nil)
  let refocusedCount = try await LorvexSystemIntentRunner.addTaskToFocus(
    id: task.id, core: core)
  #expect(refocusedCount == 1)
  let proposedSchedule = try await LorvexSystemIntentRunner.proposeFocusSchedule(
    date: nil, core: core)
  #expect(proposedSchedule.date == logicalDay)
  // The real proposal engine adds structure blocks (buffers) around the work;
  // the contract is that the focused task gets a block, not a bare 1:1 count.
  #expect(proposedSchedule.blocks.contains { $0.taskID == task.id })
  _ = try await core.saveFocusSchedule(
    date: proposedSchedule.date, blocks: proposedSchedule.blocks, rationale: "System schedule")
  let readSchedule = try #require(
    try await LorvexSystemIntentRunner.readFocusSchedule(
      date: nil, core: core))
  #expect(readSchedule.date == logicalDay)
  #expect(readSchedule.blocks.count == proposedSchedule.blocks.count)
  let clearedFocusDate = try await LorvexSystemIntentRunner.clearCurrentFocus(
    date: nil, core: core)
  #expect(clearedFocusDate == logicalDay)
  #expect(try await core.loadCurrentFocus(date: logicalDay) == nil)
  let deferredTitle = try await LorvexSystemIntentRunner.deferTaskUntilTomorrow(
    id: task.id, core: core)
  var today = try await core.loadToday()
  let deferred = try #require(today.tasks.first { $0.id == task.id })
  #expect(deferredTitle == "Shared system focus task")
  #expect(deferred.status == .open)
  #expect(deferred.plannedDate != nil)
  let completedTitle = try await LorvexSystemIntentRunner.completeTask(id: task.id, core: core)
  today = try await core.loadToday()
  #expect(completedTitle == "Shared system focus task")
  // The completed task leaves the open-only Today snapshot.
  #expect(!today.tasks.contains { $0.id == task.id })
  #expect(try await core.loadTask(id: task.id).status == .completed)
}
