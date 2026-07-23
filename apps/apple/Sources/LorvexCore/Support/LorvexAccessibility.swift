// MARK: - Task accessibility helpers

/// Localized vocabulary for `taskAccessibilityLabel`. Each rendering surface
/// supplies these from its own string catalog (LorvexApple via native,
/// bundle-qualified localization calls,
/// LorvexMobile via `MobileL10n`) so VoiceOver speaks the user's language; the
/// composition stays shared here. The defaults reproduce the original English
/// exactly, so callers that don't localize (and tests) are unaffected.
///
/// Format strings carry a single placeholder: `priorityTaskFormat` / `dueFormat`
/// / `overdueFormat` take a `%@` (the priority code or relative due label) and
/// `minutesFormat` takes a `%lld` (the estimate). A surface that uses native
/// String Catalog pluralization can instead provide `minutesText`; the format
/// remains as a compatibility fallback for callers and tests. `statusName`
/// maps a status to its localized display word.
public struct TaskAccessibilityVocabulary: Sendable {
  public var focusedTask: String
  public var priorityTaskFormat: String
  public var minutesFormat: String
  public var minutesText: (@Sendable (Int) -> String)?
  public var dueFormat: String
  public var overdueFormat: String
  public var statusName: @Sendable (LorvexTask.Status) -> String

  public init(
    focusedTask: String = "Focused task",
    priorityTaskFormat: String = "%@ task",
    minutesFormat: String = "%lld minutes",
    minutesText: (@Sendable (Int) -> String)? = nil,
    dueFormat: String = "due %@",
    overdueFormat: String = "overdue %@",
    statusName: @escaping @Sendable (LorvexTask.Status) -> String = { $0.rawValue }
  ) {
    self.focusedTask = focusedTask
    self.priorityTaskFormat = priorityTaskFormat
    self.minutesFormat = minutesFormat
    self.minutesText = minutesText
    self.dueFormat = dueFormat
    self.overdueFormat = overdueFormat
    self.statusName = statusName
  }
}

/// Returns a VoiceOver-ready label for a task row, combining priority, title, status,
/// estimated duration, due date, and tags into a single spoken description.
///
/// Example (English): "P1 task: Write release notes: open, 30 minutes, due tomorrow, #writing"
///
/// Pass a localized `vocabulary` to have the connective words spoken in the
/// user's language; the default reproduces English.
public func taskAccessibilityLabel(
  _ task: LorvexTask,
  isFocused: Bool = false,
  vocabulary: TaskAccessibilityVocabulary = TaskAccessibilityVocabulary()
) -> String {
  var parts: [String] = []

  if isFocused {
    parts.append(vocabulary.focusedTask)
  } else {
    parts.append(String(format: vocabulary.priorityTaskFormat, task.priority.rawValue))
  }

  parts.append(task.title)

  var attributes: [String] = [vocabulary.statusName(task.status)]
  if let minutes = task.estimatedMinutes {
    attributes.append(
      vocabulary.minutesText?(minutes) ?? String(format: vocabulary.minutesFormat, minutes))
  }
  if let dueLabel = task.cachedDueRelativeLabel() {
    attributes.append(
      String(format: task.isOverdue() ? vocabulary.overdueFormat : vocabulary.dueFormat, dueLabel))
  }
  for tag in task.tags {
    attributes.append("#\(tag)")
  }
  parts.append(attributes.joined(separator: ", "))

  return parts.joined(separator: ": ")
}

/// Returns a VoiceOver-ready value string for a task count badge.
///
/// Example: "3 tasks in focus" or "1 task in focus"
/// VoiceOver value for the focus-count badge. `format` is a localized template
/// taking `%lld` (the count); nil reproduces the English "N task(s) in focus".
public func focusTaskCountAccessibilityValue(_ count: Int, format: String? = nil) -> String {
  if let format { return String(format: format, count) }
  return count == 1 ? "1 task in focus" : "\(count) tasks in focus"
}

/// Returns a VoiceOver-ready accessibility label for a menu-bar icon-only action button.
///
/// Converts the action title into a consistent spoken label for VoiceOver,
/// since the button body contains only an SF Symbol image.
public func menuBarActionAccessibilityLabel(_ title: String) -> String {
  title
}

// MARK: - Habit accessibility helpers

/// Returns a VoiceOver-ready label for a habit row combining name, progress, and cue.
///
/// Example: "Morning Run, 1 of 3 completions today, every day"
/// VoiceOver label for a habit row. `progressFormat` is a localized positional
/// template taking `%1$lld` (completions today, capped) and `%2$lld` (target);
/// nil reproduces the English "N of M completions today".
public func habitAccessibilityLabel(_ habit: LorvexHabit, progressFormat: String? = nil) -> String {
  let done = min(habit.completionsToday, habit.targetCount)
  let progress =
    progressFormat.map { String(format: $0, done, habit.targetCount) }
    ?? "\(done) of \(habit.targetCount) completions today"
  var parts = [habit.name, progress, habit.frequencyType]
  if let cue = habit.cue, !cue.isEmpty { parts.append(cue) }
  return parts.joined(separator: ", ")
}

/// Returns a VoiceOver-ready label for the habit completion toggle button.
///
/// Example: "Complete today" or "Reset today"
public func habitActionAccessibilityLabel(isComplete: Bool) -> String {
  isComplete ? "Reset today" : "Complete today"
}

// MARK: - Memory entry accessibility helpers

/// Returns a VoiceOver-ready label for a memory entry row combining key and
/// content.
///
/// Example: "project_goal: Ship v1 by Q3"
public func memoryEntryAccessibilityLabel(_ entry: MemoryEntry) -> String {
  "\(entry.key): \(entry.content)"
}

// MARK: - Calendar event accessibility helpers

/// Returns a VoiceOver-ready label for a calendar event row combining title, time, and location.
///
/// Example: "Team Standup, All day, Work · External calendar"
public func calendarEventAccessibilityLabel(
  title: String, allDay: Bool, startTime: String?, endTime: String?, location: String?,
  source: String, allDayText: String = "All day"
) -> String {
  let timeText =
    allDay
    ? allDayText
    : [startTime, endTime].compactMap { $0 }.joined(separator: "-")
  let place = location.flatMap { $0.isEmpty ? nil : $0 } ?? source
  return "\(title), \(timeText), \(place)"
}

// MARK: - List accessibility helpers

/// Returns a VoiceOver-ready label for a list catalog row combining name and task counts.
///
/// Example: "Work: 4 open tasks, 10 total"
/// VoiceOver label for a list catalog row. `format` is a localized positional
/// template taking `%1$@` (name), `%2$lld` (open count), `%3$lld` (total); nil
/// reproduces the English "Name: N open task(s), M total" (with the English
/// singular/plural of "task").
public func listAccessibilityLabel(_ list: LorvexList, format: String? = nil) -> String {
  if let format {
    return String(format: format, list.name, list.openCount, list.totalCount)
  }
  return "\(list.name): \(list.openCount) open task\(list.openCount == 1 ? "" : "s"), \(list.totalCount) total"
}

// MARK: - Review accessibility helpers

/// Returns a VoiceOver-ready label for a review metric row.
///
/// Example: "Completed: 5"
public func reviewMetricAccessibilityLabel(title: String, value: Int) -> String {
  "\(title): \(value)"
}
