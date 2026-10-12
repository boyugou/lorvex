import Foundation

/// An event field that can appear as a line of an event's shared text.
public enum LorvexEventShareField: CaseIterable, Sendable {
  case when, location, repeats, attendees, url
}

/// The words an event's shared text is written in. Each surface supplies them
/// from its own string catalog, so the text reads in the user's language while
/// its layout is the same on every platform, and the same as a task's
/// (``LorvexTaskShareLabels``).
public struct LorvexEventShareLabels: Sendable {
  /// A field's name ("Location").
  public var field: @Sendable (LorvexEventShareField) -> String
  /// A field's name and its value on one line, with the punctuation the
  /// language puts between them ("Location: Studio").
  public var line: @Sendable (_ label: String, _ value: String) -> String
  /// A day and the time on it ("Friday, October 2, 9:00 – 10:30 AM"), or the
  /// day and the words for an all-day event ("Friday, October 2, All day").
  public var dayAtTime: @Sendable (_ day: String, _ time: String) -> String
  /// The words for an all-day event ("All day").
  public var allDay: String
  /// The words for a repeating event whose rule is not known ("Repeating
  /// event").
  public var repeating: String

  public init(
    field: @escaping @Sendable (LorvexEventShareField) -> String,
    line: @escaping @Sendable (_ label: String, _ value: String) -> String,
    dayAtTime: @escaping @Sendable (_ day: String, _ time: String) -> String,
    allDay: String,
    repeating: String
  ) {
    self.field = field
    self.line = line
    self.dayAtTime = dayAtTime
    self.allDay = allDay
    self.repeating = repeating
  }
}

/// The plain text an event is shared or copied as: lines in the user's
/// language that read the same in Messages, Mail, Notes, or a Markdown editor.
/// Blocks are separated by a blank line. Days are written as dates rather than
/// "tomorrow", since the text is read after the day it was shared on.
public enum LorvexEventShareText {
  /// The event in the order its detail shows it: the title, one "Label: value"
  /// line per set field (when, location, repeat rule, attendees, link), and
  /// the notes. A blank field is left out, so an event with nothing but a time
  /// is its title and its When line.
  public static func text(for event: CalendarTimelineEvent, labels: LorvexEventShareLabels) -> String {
    var blocks = [event.title]
    let rows = rows(for: event, labels: labels)
    if !rows.isEmpty {
      blocks.append(rows.map { labels.line(labels.field($0.field), $0.value) }.joined(separator: "\n"))
    }
    if let notes = nonBlank(event.notes) { blocks.append(notes) }
    return blocks.joined(separator: "\n\n")
  }

  static func rows(for event: CalendarTimelineEvent, labels: LorvexEventShareLabels)
    -> [(field: LorvexEventShareField, value: String)]
  {
    var rows: [(field: LorvexEventShareField, value: String)] = []
    let when = event.whenLines(allDay: labels.allDay)
    rows.append((.when, when.second.map { labels.dayAtTime(when.first, $0) } ?? when.first))
    if let location = nonBlank(event.location) { rows.append((.location, location)) }
    if event.hasRecurrenceRow {
      rows.append((.repeats, event.recurrenceDescription(generic: labels.repeating)))
    }
    let attendees = (event.attendees ?? []).compactMap { attendee in
      nonBlank(attendee.name) ?? nonBlank(attendee.email)
    }
    if !attendees.isEmpty { rows.append((.attendees, attendees.joined(separator: ", "))) }
    if let url = nonBlank(event.url) { rows.append((.url, url)) }
    return rows
  }

  private static func nonBlank(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }
}
