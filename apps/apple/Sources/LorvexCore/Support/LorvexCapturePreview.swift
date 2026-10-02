import SwiftUI

/// What a typed capture line will create, shown under the capture field while
/// the user types: the title left once the details are read out of the line,
/// and the details as words in the task's own vocabulary ("Tomorrow",
/// "9:30 – 10:00 AM", "Every week · Mon, Thu", "Due Friday", "Offsite"). The
/// Mac's quick-add row and the iPhone's capture sheet show the same words.
public struct LorvexCapturePreview: Equatable, Sendable {
  /// One recognized detail.
  public struct Word: Identifiable, Equatable, Sendable {
    /// What the detail is about, which decides its tint.
    public enum Role: Equatable, Sendable {
      /// The plan: the day the task is done on, its time or length, its repeat.
      case plan
      /// A deadline.
      case due
      /// Urgent now: high priority.
      case urgent
      /// Filing: the list, tags, a priority that is not high.
      case plain
    }

    /// Stable within one preview: `when`, `time`, `length`, `repeats`, `due`,
    /// `list`, `priority`, or `tag.<name>`.
    public let id: String
    public let label: String
    public let role: Role

    public var tint: Color {
      switch role {
      case .plan: LorvexDesign.Palette.accent
      case .due: LorvexDesign.Palette.dueSoon
      case .urgent: LorvexDesign.Palette.overdue
      case .plain: LorvexDesign.Palette.neutral
      }
    }
  }

  public let title: String
  public let words: [Word]

  /// The preview of a line that carries no details: no title and no words, so
  /// a plain title shows nothing under the field.
  public static let empty = LorvexCapturePreview(title: "", words: [])

  /// The text that opens the preview: "Adds “Call the caterer”".
  public var addsLine: String {
    String(
      localized: "quick_add.preview.adds", defaultValue: "Adds “\(title)”", table: "Localizable",
      bundle: CoreL10n.bundle)
  }

  private init(title: String, words: [Word]) {
    self.title = title
    self.words = words
  }

  /// The preview of `parse`, whose day offsets count from `logicalDay`.
  ///
  /// The words follow the order a task is planned in: the day it is done on,
  /// its time (whose span already says its length) or else its length, its
  /// repeat, its due day, its list, its priority, then its tags. A repeating
  /// task is due on its first occurrence; when the line named no due day and
  /// that occurrence is the planned day the preview already shows, the due day
  /// is left out, since the day word says it ("Standup every mon and thu
  /// 9:30am" shows Monday, its time, and its repeat, not "Due Monday" again).
  ///
  /// - Parameters:
  ///   - parse: the line as ``LorvexCaptureParser`` read it.
  ///   - logicalDay: the product's logical today, `yyyy-MM-dd`.
  public init(parse: LorvexCaptureParse, logicalDay: String) {
    guard parse.hasDetails else {
      self = .empty
      return
    }
    func day(_ offset: Int, _ position: LorvexDayPhrase.Position) -> String? {
      PlannedDayBridge.storageDate(forLogicalDay: logicalDay, addingDays: offset).map {
        LorvexDayPhrase.phrase(for: $0, logicalDay: logicalDay, position: position)
      }
    }
    var words: [Word] = []
    let plannedDay = parse.resolvedPlannedDayOffset
    if let plannedDay, let label = day(plannedDay, .leading) {
      words.append(Word(id: "when", label: label, role: .plan))
    }
    if let time = parse.plannedTime {
      words.append(
        Word(
          id: "time", label: lorvexClockRangeLabel(startMinutes: time.lowerBound, endMinutes: time.upperBound),
          role: .plan))
    } else if let minutes = parse.estimatedMinutes {
      words.append(Word(id: "length", label: LorvexDurationFormat.minutes(minutes), role: .plan))
    }
    if let rule = parse.recurrence {
      words.append(Word(id: "repeats", label: rule.localizedCadence, role: .plan))
    }
    if let dueDay = parse.resolvedDueDayOffset, parse.dueDayOffset != nil || dueDay != plannedDay,
      let phrase = day(dueDay, .inline)
    {
      let label = String(
        localized: "quick_add.preview.due", defaultValue: "Due \(phrase)", table: "Localizable",
        bundle: CoreL10n.bundle)
      words.append(Word(id: "due", label: label, role: .due))
    }
    if let listName = parse.listName {
      words.append(Word(id: "list", label: listName, role: .plain))
    }
    if let priority = parse.priority {
      words.append(Word(id: "priority", label: priority.localizedPhrase, role: priority == .p1 ? .urgent : .plain))
    }
    for tag in parse.tags {
      words.append(Word(id: "tag.\(tag)", label: "#\(tag)", role: .plain))
    }
    self.init(title: parse.title, words: words)
  }
}
