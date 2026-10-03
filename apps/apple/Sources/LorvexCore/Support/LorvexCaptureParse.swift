import Foundation

/// What a typed capture line says beyond its title.
///
/// Capture and the task detail share one vocabulary: the phrases this parser
/// recognizes become the same words the detail's property sentence shows, so
/// typing "Call the caterer tomorrow 20 min #offsite" creates the task the
/// sentence would describe as "Tomorrow for 20 min. In Offsite." Recognized
/// phrases are removed from the title; everything else stays verbatim.
///
/// Days are offsets from the product's logical today, so the caller converts
/// them through its own logical-day bridge rather than a device calendar.
public struct LorvexCaptureParse: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case when, due, time, repeats, length, list, priority, tag
  }

  /// One recognized phrase, in the order it appeared.
  public struct Phrase: Equatable, Sendable {
    public var kind: Kind
    /// The text as typed ("tomorrow", "20 min", "#offsite").
    public var text: String
  }

  public var title: String
  /// Days after the logical today the task is planned for.
  public var plannedDayOffset: Int?
  /// Days after the logical today the task is due.
  public var dueDayOffset: Int?
  public var estimatedMinutes: Int?
  /// The clock time the line named ("3pm", "下午3点"), in minutes since
  /// midnight.
  public var startMinutes: Int?
  /// How the task repeats ("every Monday", 每天).
  public var recurrence: TaskRecurrenceRule?
  /// Days after the logical today of the rule's first occurrence, when the
  /// rule fixes one: the next of its weekdays, or of its day of the month,
  /// today included.
  public var recurrenceStartOffset: Int?
  /// A list the text named with `#name`, matched against the known lists.
  public var listID: String?
  public var listName: String?
  public var priority: LorvexTask.Priority?
  /// `#words` that matched no list.
  public var tags: [String]
  public var phrases: [Phrase]

  public var hasDetails: Bool { !phrases.isEmpty }

  /// The day a task created from the line is planned for: the day it named,
  /// or the logical today when it named only a clock time, since a time
  /// belongs to a day.
  public var resolvedPlannedDayOffset: Int? {
    plannedDayOffset ?? (startMinutes == nil ? nil : (recurrence == nil ? 0 : resolvedDueDayOffset))
  }

  /// The day a task created from the line is due. A repeating task needs a
  /// due day, its first occurrence: the due day the line named, else the
  /// rule's first occurrence, else the planned day, else the logical today.
  public var resolvedDueDayOffset: Int? {
    guard recurrence != nil else { return dueDayOffset }
    return dueDayOffset ?? recurrenceStartOffset ?? plannedDayOffset ?? 0
  }

  /// The task's time on its planned day: from the clock time the line named,
  /// for its length or half an hour, kept inside the day.
  public var plannedTime: Range<Int>? {
    startMinutes.map {
      LorvexTaskFieldChoices.time(
        LorvexTaskFieldChoices.newTime(length: estimatedMinutes, nowMinutes: nil, isToday: false),
        movingStartTo: $0)
    }
  }
}
