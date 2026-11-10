import Foundation

/// One task's time on a day, as saved or suggested: minutes since midnight in
/// the configured timezone, running forward within the day and ending at most
/// at 1440, midnight at the day's end.
public struct LorvexTaskTime: Equatable, Sendable {
  public var taskID: LorvexTask.ID
  public var time: Range<Int>

  public init(taskID: LorvexTask.ID, time: Range<Int>) {
    self.taskID = taskID
    self.time = time
  }
}

/// Suggested times for one day's tasks: the tasks laid into the free working
/// time, around the day's calendar events, in Today's order. On today the
/// suggestion starts at the current time. A task whose time is under way keeps
/// it, a task without an estimate takes 30 minutes, and work whose time passed
/// unfinished is placed again. Nothing is stored until the user accepts
/// (``times``).
public struct DayTimesProposal: Equatable, Sendable {
  /// A task and the time the suggestion gives it.
  public struct Placement: Identifiable, Equatable, Sendable {
    public var task: LorvexTask
    public var time: Range<Int>
    public var id: LorvexTask.ID { task.id }

    public init(task: LorvexTask, time: Range<Int>) {
      self.task = task
      self.time = time
    }
  }

  /// A calendar event the suggestion worked around, described as far as the
  /// calendar access setting for assistants allows.
  public struct Event: Equatable, Sendable {
    /// Where the event comes from.
    public enum Source: String, Equatable, Sendable {
      /// A Lorvex calendar event, synced with the user's data.
      case canonical
      /// An event of a calendar on this device.
      case provider
    }

    /// The part of the event inside the working window, in minutes since
    /// midnight.
    public var time: Range<Int>
    /// The event's title, or nil for a device calendar event when the access
    /// setting shares only busy time.
    public var title: String?
    /// The Lorvex event's id; nil for a device calendar event.
    public var eventID: String?
    public var source: Source

    public init(time: Range<Int>, title: String?, eventID: String?, source: Source) {
      self.time = time
      self.title = title
      self.eventID = eventID
      self.source = source
    }
  }

  /// The day, `yyyy-MM-dd`.
  public var date: String
  /// The working window the suggestion filled, in minutes since midnight.
  public var workingHours: Range<Int>
  /// Working minutes left free by the day's events, from the suggestion's
  /// start.
  public var availableMinutes: Int
  /// The placed tasks, in start order.
  public var placements: [Placement]
  /// The events the suggestion worked around, in start order.
  public var events: [Event]
  /// The tasks that did not fit, in Today's order.
  public var unscheduled: [LorvexTask]

  public init(
    date: String, workingHours: Range<Int>, availableMinutes: Int, placements: [Placement],
    events: [Event] = [], unscheduled: [LorvexTask] = []
  ) {
    self.date = date
    self.workingHours = workingHours
    self.availableMinutes = availableMinutes
    self.placements = placements
    self.events = events
    self.unscheduled = unscheduled
  }

  /// The times saved when the user accepts.
  public var times: [LorvexTaskTime] {
    placements.map { LorvexTaskTime(taskID: $0.task.id, time: $0.time) }
  }

  /// True when the working time left had room for none of the tasks.
  public var placesNothing: Bool { placements.isEmpty && !unscheduled.isEmpty }

  /// The times to store when the suggestion is accepted, for the day as it
  /// stands at that moment.
  ///
  /// A suggestion is drawn against the day as it stood when it was asked for,
  /// and accepting it replaces the day's times. A time set after that (in a
  /// task's editor, by a drag, by the assistant) would be overwritten, or
  /// removed when the suggestion does not list the task. So a task whose time
  /// differs from the one it had when the suggestion was drawn keeps what it
  /// has now, whether that is another time or none, and a task that has since
  /// left the day's unfinished work (finished, moved to another day) is left
  /// out rather than pulled back.
  ///
  /// `timedWhenSuggested` and `timedNow` hold the times of the day's
  /// unfinished tasks then and now; `unfinishedToday` is the unfinished tasks
  /// on the day now.
  public func timesToStore(
    timedWhenSuggested: [LorvexTask.ID: Range<Int>],
    timedNow: [LorvexTask.ID: Range<Int>],
    unfinishedToday: Set<LorvexTask.ID>
  ) -> [LorvexTaskTime] {
    var result: [LorvexTaskTime] = []
    var suggested = Set<LorvexTask.ID>()
    for entry in times {
      suggested.insert(entry.taskID)
      guard unfinishedToday.contains(entry.taskID) else { continue }
      if timedWhenSuggested[entry.taskID] == timedNow[entry.taskID] {
        result.append(entry)
      } else if let time = timedNow[entry.taskID] {
        result.append(LorvexTaskTime(taskID: entry.taskID, time: time))
      }
    }
    // A task the suggestion did not place that has been given a time since.
    for (taskID, time) in timedNow.sorted(by: { $0.key < $1.key })
    where !suggested.contains(taskID) && unfinishedToday.contains(taskID)
      && timedWhenSuggested[taskID] != time
    {
      result.append(LorvexTaskTime(taskID: taskID, time: time))
    }
    return result
  }
}

extension LorvexDayPlanningServicing {
  /// The times of `date`'s unfinished tasks, by task: what a suggestion is
  /// drawn against, and what accepting it is reconciled with
  /// (``DayTimesProposal/timesToStore(timedWhenSuggested:timedNow:unfinishedToday:)``).
  public func unfinishedTaskTimes(on date: String) async throws -> [LorvexTask.ID: Range<Int>] {
    var times: [LorvexTask.ID: Range<Int>] = [:]
    for task in try await loadTimedTasks(from: date, through: date)
    where task.status.isActionable {
      if let time = task.time(on: date) { times[task.id] = time }
    }
    return times
  }
}
