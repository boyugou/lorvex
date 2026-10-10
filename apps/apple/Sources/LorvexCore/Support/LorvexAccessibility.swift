import Foundation

// MARK: - Task accessibility helpers

/// Returns a VoiceOver-ready label for a task row, in the app's language: its
/// title, then the facts the row shows — a priority other than normal, a
/// status other than open, its time on the day, what the row adds beyond the
/// task's own fields, the estimate, the due day, whether it repeats, and its
/// tags.
///
/// Example (English): "Write release notes: High priority, In Progress,
/// 9:45 – 10:30 AM, 30 minutes, due tomorrow, repeats, #writing"
///
/// Normal priority and the open status are what a task is unless it says
/// otherwise, so they are not read, just as the row does not mark them.
/// `timeLabel` is the task's time on the surface's day, which leads the row's
/// metadata on Today. `details` are what the row shows beyond the task's own
/// fields — its status chips, a blocked badge, its list on a cross-list
/// surface — already localized and in the row's order. The due day is counted
/// from today in `timeZone`, the product time zone a row's other facts are
/// counted in.
public func taskAccessibilityLabel(
  _ task: LorvexTask,
  timeLabel: String? = nil,
  details: [String] = [],
  timeZone: TimeZone = .current
) -> String {
  var facts: [String] = []
  if task.priority != .p2 {
    facts.append(task.priority.localizedPhrase)
  }
  if task.status != .open {
    facts.append(task.status.localizedName)
  }
  if let timeLabel {
    facts.append(timeLabel)
  }
  facts.append(contentsOf: details)
  if let minutes = task.estimatedMinutes {
    facts.append(LorvexDurationFormat.minutes(minutes, style: .spoken))
  }
  if let due = taskDueAccessibilityPhrase(task, timeZone: timeZone) {
    facts.append(due)
  }
  if task.recurrence != nil {
    facts.append(
      String(localized: "a11y.task.repeats", defaultValue: "repeats", table: "Localizable", bundle: CoreL10n.bundle))
  }
  for tag in task.tags {
    facts.append("#\(tag)")
  }
  return facts.isEmpty ? task.title : "\(task.title): \(facts.joined(separator: ", "))"
}

/// What VoiceOver reads after a dependency's title in a task's Waits On
/// section, in the app's language: its status, then when an unfinished one is
/// due ("In Progress, due tomorrow"). A dependency row's circle and facts line
/// are not read aloud, so the status is always named, open included.
public func taskDependencyAccessibilityValue(_ task: LorvexTask, timeZone: TimeZone) -> String {
  var parts = [task.status.localizedName]
  if !task.status.isResolved, let due = taskDueAccessibilityPhrase(task, timeZone: timeZone) {
    parts.append(due)
  }
  return parts.joined(separator: ", ")
}

/// The due day as VoiceOver reads it ("due tomorrow", "overdue 2 days ago"),
/// counted from today in `timeZone`; `nil` for a task without a due day. The
/// distance is worded in full, where a row's chip abbreviates it ("2d ago").
private func taskDueAccessibilityPhrase(_ task: LorvexTask, timeZone: TimeZone) -> String? {
  guard let day = task.cachedDueRelativeLabel(timeZone: timeZone, unitsStyle: .full) else { return nil }
  return task.isOverdue(timeZone: timeZone)
    ? String(
      localized: "a11y.task.overdue_format", defaultValue: "overdue \(day)", table: "Localizable",
      bundle: CoreL10n.bundle)
    : String(
      localized: "a11y.task.due_format", defaultValue: "due \(day)", table: "Localizable", bundle: CoreL10n.bundle)
}

// MARK: - Memory entry accessibility helpers

/// Returns a VoiceOver-ready label for a memory entry row combining the
/// entry's title (``MemoryEntry/displayTitle``) and content.
///
/// Example: "Project goal: Ship v1 by Q3"
public func memoryEntryAccessibilityLabel(_ entry: MemoryEntry) -> String {
  "\(entry.displayTitle): \(entry.content)"
}

// MARK: - Calendar event accessibility helpers

/// A VoiceOver label for a timed calendar event: its title, its time, and its
/// location when it has one. An event that runs into a later day reads as one
/// span from its start day and time to its end day and time
/// (``CalendarTimelineEvent/timedSpanLabel``), one within a day as its clock
/// times.
///
/// Example: "Standup, 9:00 – 9:30 AM, Zoom"
public func calendarEventAccessibilityLabel(_ event: CalendarTimelineEvent) -> String {
  let time =
    event.timedSpanLabel ?? event.startTime.map { lorvexClockRangeLabel(start: $0, end: event.endTime) }
  let location = event.location.flatMap { $0.isEmpty ? nil : $0 }
  return [event.title, time, location].compactMap { $0 }.joined(separator: ", ")
}
