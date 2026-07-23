import Foundation
import LorvexDomain
import LorvexStore

/// Maps the core's current-focus and focus-schedule shapes onto the app's
/// `CurrentFocusPlan` / `FocusSchedule` model types, preserving the stable
/// MCP/UI field shape.
///
/// The pure-Swift core has no `focus.current.*` / `focus.schedule.*` JSON
/// envelope — these helpers lower the typed store/workflow values
/// (`CurrentFocusItemsRepo` rows, `FocusScheduleProposal.Proposal`,
/// `FocusScheduleBlocksRepo` rows) directly. `TimeOfDay` minute offsets render
/// as `HH:MM` via `.asString`, matching the public string fields.
enum SwiftLorvexFocusDeserializers {

  /// A `current_focus` header (briefing + timezone) plus its ordered task ids.
  static func currentFocusPlan(
    date: String,
    taskIDs: [String],
    briefing: String?,
    timezone: String?,
    localChangeSequence: Int
  ) -> CurrentFocusPlan {
    CurrentFocusPlan(
      date: date,
      taskIDs: taskIDs,
      briefing: briefing,
      timezone: timezone,
      localChangeSequence: localChangeSequence)
  }

  /// Lower a planner `Proposal` onto the app `FocusSchedule`. `slots` and
  /// `unscheduled` only exist on a freshly-proposed schedule; a saved schedule
  /// (blocks read back from `focus_schedule_blocks`) leaves them empty.
  static func schedule(
    _ proposal: FocusScheduleProposal.Proposal,
    timezone: String?
  ) -> FocusSchedule {
    FocusSchedule(
      date: proposal.date.asString,
      rationale: nil,
      timezone: timezone,
      workingHours: FocusScheduleWorkingHours(
        start: proposal.workingHours.start.asString,
        end: proposal.workingHours.end.asString),
      totalMinutesAvailable: Int(proposal.totalMinutesAvailable),
      calendarEventsCount: proposal.calendarEventsCount,
      blocks: proposal.blocks.map(block),
      slots: proposal.slots.map(slot),
      unscheduled: proposal.unscheduled.map(task))
  }

  /// Lower a persisted schedule (header + materialized blocks) onto the app
  /// `FocusSchedule`. Slots / unscheduled / working-hours / counts are not
  /// stored, so they read as their empty/nil defaults.
  static func schedule(
    date: String,
    rationale: String?,
    timezone: String?,
    blocks: [FocusScheduleBlock]
  ) -> FocusSchedule {
    FocusSchedule(
      date: date,
      rationale: rationale,
      timezone: timezone,
      workingHours: nil,
      totalMinutesAvailable: nil,
      calendarEventsCount: nil,
      blocks: blocks,
      slots: [],
      unscheduled: [])
  }

  static func block(_ block: FocusScheduleProposal.Block) -> FocusScheduleBlock {
    FocusScheduleBlock(
      blockType: block.blockType,
      startTime: block.startTime.asString,
      endTime: block.endTime.asString,
      taskID: block.taskId,
      calendarEventID: block.calendarEventId,
      eventSource: block.eventSource,
      title: block.title)
  }

  static func slot(_ slot: FocusScheduleProposal.Slot) -> FocusScheduleSlot {
    FocusScheduleSlot(
      task: task(slot.task),
      startTime: slot.startTime.asString,
      endTime: slot.endTime.asString)
  }

  static func task(_ task: FocusScheduleProposal.Task) -> FocusScheduleTask {
    FocusScheduleTask(
      id: task.id,
      title: task.title,
      status: task.status,
      estimatedMinutes: task.estimatedMinutes.map(Int.init))
  }
}
