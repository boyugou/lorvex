import Foundation
import LorvexCore
import LorvexDomain
import MCP

extension CoreBridgeClient {
  func proposeDayTimes(
    date: String,
    workingHoursStart: String?,
    workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> Value {
    Self.dayTimesProposalValue(
      from: try await service.proposeDayTimes(
        date: date, workingHoursStart: workingHoursStart, workingHoursEnd: workingHoursEnd,
        includeCalendarEvents: includeCalendarEvents))
  }

  /// `{date, timed_tasks}`: every task timed on `date`, in start order, in the
  /// compact task shape.
  func loadDayTimes(date: String) async throws -> Value {
    let tasks = try await service.loadTimedTasks(from: date, through: date)
    return .object([
      "date": .string(date),
      "timed_tasks": Self.taskValues(from: tasks, options: .compact),
    ])
  }

  /// Save `date`'s times from the raw `times` entries (`{task_id, start_time,
  /// end_time}`) and return `{date, timed_tasks, cleared_tasks}` as full task
  /// objects. Every entry is validated before anything is written.
  func saveDayTimes(date: String, times entries: [Value]) async throws -> Value {
    let times: [LorvexTaskTime] = try entries.enumerated().map { index, entry in
      guard let object = entry.objectValue else {
        throw ValidationError.invalidFormat(
          field: "times[\(index)]", expected: "an object {task_id, start_time, end_time}",
          actual: StrictArgumentArray.describe(entry))
      }
      let taskID = try StrictScalarArguments.string(
        object["task_id"], field: "times[\(index)].task_id", default: "")
      guard !taskID.isEmpty else {
        throw ValidationError.invalidFormat(
          field: "times[\(index)].task_id", expected: "a task id", actual: "nothing")
      }
      let time = try Self.clockRange(
        start: try StrictScalarArguments.string(
          object["start_time"], field: "times[\(index)].start_time", default: ""),
        end: try StrictScalarArguments.string(
          object["end_time"], field: "times[\(index)].end_time", default: ""),
        startField: "times[\(index)].start_time", endField: "times[\(index)].end_time")
      return LorvexTaskTime(taskID: taskID, time: time)
    }
    let receipt = try await mcpMutations.saveDayTimesForMcp(date: date, times: times)
    return .object([
      "date": .string(receipt.date),
      "timed_tasks": Self.taskValues(from: receipt.timedTasks),
      "cleared_tasks": Self.taskValues(from: receipt.clearedTasks),
    ])
  }
}
