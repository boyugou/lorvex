import Foundation
import LorvexDomain
import LorvexWorkflow

extension UserFacingError {
  /// A failure a person can cause from the app whose wording the app owns, so
  /// the alert reads in the interface language instead of the core's English
  /// message.
  ///
  /// The core throws each of these as a typed error, and ``init(_:)``
  /// recognizes them by case, never by message text:
  ///
  /// - a ``ValidationError/tooLong(field:max:actual:)`` for a task's title,
  ///   notes (`body`), a tag, or any other text field;
  /// - a ``LorvexCoreError/conflict(message:entity:)`` whose `entity` names the
  ///   tag or memory being renamed onto another one's name;
  /// - a ``CalendarEventOpError/startTimeSkipped(time:date:timezone:)`` for an
  ///   event starting inside a daylight-saving gap;
  /// - a ``TaskLifecycleError`` for a status change the task refuses: starting
  ///   a task whose dependencies are not finished, starting a done, canceled,
  ///   or Someday task, completing a canceled task, canceling a done task, or
  ///   pausing a task that is not in progress;
  /// - a ``HabitReminderError/timeTaken(habitId:time:)`` for a second habit
  ///   reminder at the same time.
  ///
  /// ``localizedMessage`` reads the LorvexCore catalog, so macOS, iOS, and
  /// every other surface show the same translation. The MCP boundary never sees
  /// a reason: it renders the error's own English description.
  public enum Reason: String, Sendable, Equatable, Codable, CaseIterable {
    /// A task title longer than its limit.
    case titleTooLong
    /// Task notes longer than their limit.
    case notesTooLong
    /// A tag longer than its limit.
    case tagTooLong
    /// Any other text a person wrote that is longer than its limit.
    case textTooLong
    /// A tag renamed onto the name of another tag.
    case tagNameTaken
    /// A memory renamed onto the name of another memory.
    case memoryNameTaken
    /// A timed event starting at a time the clocks skip when daylight saving
    /// time begins.
    case calendarTimeSkipped
    /// Starting a task whose dependencies are not all finished.
    case taskStartBlocked
    /// Starting a task that is already done.
    case startingDoneTask
    /// Starting a task that was canceled.
    case startingCanceledTask
    /// Starting a task parked in Someday.
    case startingSomedayTask
    /// Completing a task that was canceled.
    case completingCanceledTask
    /// Canceling a task that is already done.
    case cancelingDoneTask
    /// Pausing a task that is not in progress.
    case pausingUnstartedTask
    /// A habit reminder at a time the habit already has one.
    case habitReminderTimeTaken

    /// The reason `error` carries, or `nil` when it is none of the typed
    /// failures above.
    public init?(_ error: Error) {
      if case let ValidationError.tooLong(field, _, _) = error {
        switch field {
        case "title": self = .titleTooLong
        case "body": self = .notesTooLong
        case "tag", "tags": self = .tagTooLong
        default: self = .textTooLong
        }
        return
      }
      if case let LorvexCoreError.conflict(_, entity?) = error {
        switch entity {
        case .tag: self = .tagNameTaken
        case .memory: self = .memoryNameTaken
        case .list, .habit, .calendarEvent, .calendarSeries: return nil
        }
        return
      }
      if case CalendarEventOpError.startTimeSkipped = error {
        self = .calendarTimeSkipped
        return
      }
      if let lifecycle = error as? TaskLifecycleError {
        switch lifecycle {
        case .startBlockedByDependencies: self = .taskStartBlocked
        case .startRequiresOpenTask(.completed): self = .startingDoneTask
        case .startRequiresOpenTask(.cancelled): self = .startingCanceledTask
        case .startRequiresOpenTask(.someday): self = .startingSomedayTask
        case .startRequiresOpenTask(.open), .startRequiresOpenTask(.inProgress): return nil
        case .finishedTaskTransition(_, from: .cancelled, to: .completed):
          self = .completingCanceledTask
        case .finishedTaskTransition(_, from: .completed, to: .cancelled):
          self = .cancelingDoneTask
        case .finishedTaskTransition: return nil
        case .pauseRequiresStartedTask: self = .pausingUnstartedTask
        }
        return
      }
      if case HabitReminderError.timeTaken = error {
        self = .habitReminderTimeTaken
        return
      }
      return nil
    }

    /// The sentence an alert shows for this reason, in the interface language.
    public var localizedMessage: String {
      switch self {
      case .titleTooLong:
        String(
          localized: "error.reason.title_too_long",
          defaultValue: "This title is too long. Shorten it and try again.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .notesTooLong:
        String(
          localized: "error.reason.notes_too_long",
          defaultValue: "These notes are too long. Shorten them and try again.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .tagTooLong:
        String(
          localized: "error.reason.tag_too_long",
          defaultValue: "A tag is too long. Shorten it and try again.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .textTooLong:
        String(
          localized: "error.reason.text_too_long",
          defaultValue: "This text is too long. Shorten it and try again.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .tagNameTaken:
        String(
          localized: "error.reason.tag_name_taken",
          defaultValue: "A tag with this name already exists. Choose another name.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .memoryNameTaken:
        String(
          localized: "error.reason.memory_name_taken",
          defaultValue: "A memory with this name already exists. Choose another name.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .calendarTimeSkipped:
        String(
          localized: "error.reason.calendar_time_skipped",
          defaultValue:
            "This time doesn’t exist on that day because the clocks move forward for daylight saving time. Pick an earlier or later time.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .taskStartBlocked:
        String(
          localized: "error.reason.task_start_blocked",
          defaultValue: "This task depends on tasks that aren’t done yet. Finish or cancel them first.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .startingDoneTask:
        String(
          localized: "error.reason.starting_done_task",
          defaultValue: "This task is already done. Reopen it before starting it.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .startingCanceledTask:
        String(
          localized: "error.reason.starting_canceled_task",
          defaultValue: "This task was canceled. Reopen it before starting it.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .startingSomedayTask:
        String(
          localized: "error.reason.starting_someday_task",
          defaultValue: "This task is in Someday. Reopen it before starting it.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .completingCanceledTask:
        String(
          localized: "error.reason.completing_canceled_task",
          defaultValue: "This task was canceled. Reopen it before completing it.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .cancelingDoneTask:
        String(
          localized: "error.reason.canceling_done_task",
          defaultValue: "This task is already done. Reopen it before canceling it.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .pausingUnstartedTask:
        String(
          localized: "error.reason.pausing_unstarted_task",
          defaultValue: "Only a task in progress can be paused.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .habitReminderTimeTaken:
        String(
          localized: "error.reason.habit_reminder_time_taken",
          defaultValue: "This habit already has a reminder at that time. Choose another time.",
          table: "Localizable", bundle: CoreL10n.bundle)
      }
    }
  }
}
