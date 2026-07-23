import Foundation
import LorvexCore
import MCP

/// Maps the `LorvexCore` focus plan and focus schedule model types onto the MCP
/// `Value` JSON shapes the focus tool handlers return. Field names and shapes
/// mirror the contract expected by existing MCP clients, so external
/// integrations see stable objects while the implementation stays pure Swift.
extension CoreBridgeClient {
  static func currentFocusValue(from plan: CurrentFocusPlan) -> Value {
    var value: [String: Value] = [
      "task_count": .int(plan.taskIDs.count),
      "task_ids": .array(plan.taskIDs.map(Value.string)),
      "date": .string(plan.date),
    ]
    if let briefing = plan.briefing {
      value["briefing"] = .string(briefing)
    }
    if let timezone = plan.timezone {
      value["timezone"] = .string(timezone)
    }
    return .object(value)
  }

  static func focusScheduleValue(from schedule: FocusSchedule) -> Value {
    var value: [String: Value] = [
      "date": .string(schedule.date),
      "rationale": schedule.rationale.map(Value.string) ?? .null,
      "timezone": schedule.timezone.map(Value.string) ?? .null,
      "total_minutes_available": schedule.totalMinutesAvailable.map(Value.int) ?? .null,
      "calendar_events_count": schedule.calendarEventsCount.map(Value.int) ?? .null,
      "blocks": .array(schedule.blocks.map(focusScheduleBlockValue(from:))),
      "slots": .array(schedule.slots.map(focusScheduleSlotValue(from:))),
      "unscheduled": .array(schedule.unscheduled.map(focusScheduleTaskValue(from:))),
    ]
    if let workingHours = schedule.workingHours {
      value["working_hours"] = .object([
        "start": .string(workingHours.start),
        "end": .string(workingHours.end),
      ])
    } else {
      value["working_hours"] = .null
    }
    return .object(value)
  }

  static func focusScheduleBlockValue(from block: FocusScheduleBlock) -> Value {
    .object([
      "block_type": .string(block.blockType),
      "start_time": .string(block.startTime),
      "end_time": .string(block.endTime),
      "task_id": block.taskID.map(Value.string) ?? .null,
      "event_id": block.calendarEventID.map(Value.string) ?? .null,
      "event_source": block.eventSource.map { .string($0.rawValue) } ?? .null,
      "title": block.title.map(Value.string) ?? .null,
    ])
  }

  static func focusScheduleTaskValue(from task: FocusScheduleTask) -> Value {
    .object([
      "id": .string(task.id),
      "title": .string(task.title),
      "status": .string(task.status),
      "estimated_minutes": task.estimatedMinutes.map(Value.int) ?? .null,
    ])
  }

  static func focusScheduleSlotValue(from slot: FocusScheduleSlot) -> Value {
    .object([
      "task": focusScheduleTaskValue(from: slot.task),
      "start_time": .string(slot.startTime),
      "end_time": .string(slot.endTime),
    ])
  }
}
