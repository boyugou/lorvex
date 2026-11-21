/// The destination day with the chosen unfinished tasks added to its load.
public struct ReviewTomorrowLoad {
  public let meetingMinutes: Int
  public let existingMinutes: Int
  public let selectedMinutes: Int
  public let unknownCount: Int
  public var plannedMinutes: Int { meetingMinutes + existingMinutes + selectedMinutes }

  public init(agenda: LorvexAgendaDay, window: Range<Int>, selected: [ReviewTaskSummary]) {
    let input = LorvexWeekLoad.DayInput(key: agenda.key, events: agenda.events, tasks: agenda.tasks)
    let load = LorvexWeekLoad.build(days: [input], todayKey: agenda.key,
      workStart: window.lowerBound, workEnd: window.upperBound).days[0]
    meetingMinutes = load.meetingMinutes
    existingMinutes = load.taskMinutes
    let estimates = selected.compactMap(\.estimatedMinutes)
    selectedMinutes = estimates.reduce(0, +)
    unknownCount = selected.count - estimates.count + agenda.tasks.filter {
      $0.estimatedMinutes == nil && $0.time(on: agenda.key) == nil
    }.count
  }
}
