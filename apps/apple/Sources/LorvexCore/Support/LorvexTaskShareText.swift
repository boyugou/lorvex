import Foundation

/// A task field that can appear as a line of a task's shared text.
public enum LorvexTaskShareField: CaseIterable, Sendable {
  case doOn, estimate, due, list, priority, recurrence, tags, hideUntil
}

/// The words a task's shared text is written in. Each surface supplies them
/// from its own string catalog, so the text reads in the user's language while
/// its layout is the same on every platform.
public struct LorvexTaskShareLabels: Sendable {
  /// A field's name ("Due").
  public var field: @Sendable (LorvexTaskShareField) -> String
  /// A field's name and its value on one line, with the punctuation the
  /// language puts between them ("Due: Tue, Sep 29, 2026").
  public var line: @Sendable (_ label: String, _ value: String) -> String
  /// A planned day with the task's time on it ("Mon, Sep 28, 2026, 9:45 –
  /// 10:30 AM"); `range` is minutes since midnight.
  public var dayAtTime: @Sendable (_ day: String, _ range: Range<Int>) -> String
  /// The heading of the assistant's notes.
  public var assistantContext: String
  /// The heading of the checklist.
  public var checklist: String

  public init(
    field: @escaping @Sendable (LorvexTaskShareField) -> String,
    line: @escaping @Sendable (_ label: String, _ value: String) -> String,
    dayAtTime: @escaping @Sendable (_ day: String, _ range: Range<Int>) -> String,
    assistantContext: String,
    checklist: String
  ) {
    self.field = field
    self.line = line
    self.dayAtTime = dayAtTime
    self.assistantContext = assistantContext
    self.checklist = checklist
  }
}

/// The plain text a task is shared or copied as: lines in the user's language
/// that read the same in Messages, Mail, Notes, or a Markdown editor. Blocks
/// are separated by a blank line, a section is its name on one line with its
/// content below, and a checklist item starts with "- [ ]" or "- [x]". Days
/// are written as dates rather than "tomorrow", since the text is read after
/// the day it was shared on.
public enum LorvexTaskShareText {
  /// The task in the order its detail shows it: the title, the status when
  /// the task is not open, the notes, one "Label: value" line per set field,
  /// the assistant context, and the checklist (`- [x]` for a finished item).
  /// A blank notes or assistant context is left out, so an open task with
  /// nothing set is its title alone.
  ///
  /// - Parameters:
  ///   - listName: the task's list name, or `nil` when it has none.
  ///   - logicalDay: the product's logical today, `yyyy-MM-dd`; it anchors a
  ///     weekly repeat that names no weekday and decides whether a hide-until
  ///     day is still ahead.
  public static func text(
    for task: LorvexTask, listName: String?, logicalDay: String, labels: LorvexTaskShareLabels
  ) -> String {
    var blocks: [String] = []
    blocks.append(
      task.status == .open ? task.title : "\(task.title)\n\(task.status.localizedName)")
    if let notes = nonBlank(task.notes) { blocks.append(notes) }
    let rows = rows(for: task, listName: listName, logicalDay: logicalDay, dayAtTime: labels.dayAtTime)
    if !rows.isEmpty {
      blocks.append(rows.map { labels.line(labels.field($0.field), $0.value) }.joined(separator: "\n"))
    }
    if let aiNotes = nonBlank(task.aiNotes) {
      blocks.append("\(labels.assistantContext)\n\(aiNotes)")
    }
    if !task.checklistItems.isEmpty {
      let items = task.checklistItems.sorted { $0.position < $1.position }
        .map { "- [\($0.completedAt == nil ? " " : "x")] \($0.text)" }
      blocks.append("\(labels.checklist)\n\(items.joined(separator: "\n"))")
    }
    return blocks.joined(separator: "\n\n")
  }

  /// One row per set field, in the order a person plans a task: when and for
  /// how long, the deadline, where it belongs and how urgent it is, how it
  /// repeats, its tags, and the day it is hidden until. A normal priority and a
  /// hide-until day that has arrived are not rows, since neither says anything.
  static func rows(
    for task: LorvexTask, listName: String?, logicalDay: String,
    dayAtTime: (String, Range<Int>) -> String
  ) -> [(field: LorvexTaskShareField, value: String)] {
    var rows: [(field: LorvexTaskShareField, value: String)] = []
    func add(_ field: LorvexTaskShareField, _ value: String?) {
      if let value { rows.append((field, value)) }
    }
    add(
      .doOn,
      task.plannedDate.map { planned in
        let day = dated(planned)
        return task.plannedTime.map { dayAtTime(day, $0) } ?? day
      })
    add(.estimate, task.estimatedMinutes.flatMap { $0 > 0 ? LorvexDurationFormat.minutes($0) : nil })
    add(.due, task.dueDate.map(dated))
    add(.list, listName)
    add(.priority, task.priority == .p2 ? nil : task.priority.localizedName)
    add(
      .recurrence,
      task.recurrence?.localizedCadence(anchorDay: task.recurrenceAnchorDay(logicalDay: logicalDay)))
    add(.tags, task.tags.isEmpty ? nil : task.tags.joined(separator: " · "))
    add(
      .hideUntil,
      task.availableFrom.flatMap { (lorvexDayOffset(from: logicalDay, to: $0) ?? 1) > 0 ? dated($0) : nil })
    return rows
  }

  /// A stored day as a date with its weekday and year, in the user's language
  /// ("Tue, Sep 29, 2026", "2026年9月29日周二"). The stored day names a calendar
  /// day, so it is written in UTC and never shifts across time zones.
  static func dated(_ day: Date) -> String {
    LorvexDateFormatters.string(day, template: "yMMMEd", timeZone: .gmt)
  }

  private static func nonBlank(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }
}
