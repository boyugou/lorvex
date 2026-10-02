import Foundation
import LorvexCore

/// The words of the macOS day and week reviews. The review-sentence keys
/// match the iPhone copy so both platforms word the same day the same way.
enum ReviewCalmCopy {
  /// The review sentence: each part worded, joined the way its language
  /// separates sentences (``LorvexReviewSentence/join(_:)``).
  static func sentence(_ parts: [LorvexReviewSentence.Part]) -> String {
    LorvexReviewSentence.join(parts.map(word))
  }

  static func word(_ part: LorvexReviewSentence.Part) -> String {
    switch part {
    case .quiet:
      return String(localized: "review.calm.quiet", defaultValue: "A quiet day.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .finished(let count):
      return String(localized: "review.calm.finished", defaultValue: "You finished \(count) tasks.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .nothingFinished:
      return String(localized: "review.calm.nothing_finished", defaultValue: "Nothing was finished.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .stillDue(let count):
      return String(localized: "review.calm.still_due", defaultValue: "\(count) due tasks are still open.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .habitsAll:
      return String(localized: "review.calm.habits_all", defaultValue: "Every habit kept.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .habitsSome(let kept, let total):
      return String(localized: "review.calm.habits_some", defaultValue: "\(kept)\u{00A0}of\u{00A0}\(total) habits kept.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .habitsNone:
      return String(localized: "review.calm.habits_none", defaultValue: "No habits kept.", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  static var feelLabel: String { String(localized: "review.calm.feel", defaultValue: "How did it feel?", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var feelLow: String { String(localized: "review.calm.feel.low", defaultValue: "Rough", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var feelHigh: String { String(localized: "review.calm.feel.high", defaultValue: "Great", table: "Localizable", bundle: LorvexL10n.bundle) }
  static func feelDot(_ level: Int) -> String {
    String(localized: "review.calm.feel.dot", defaultValue: "Feeling \(level) of 5", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  /// The word for one feeling level 1–5, named under the scale.
  static func feelWord(_ level: Int) -> String {
    switch level {
    case 1: feelLow
    case 2: String(localized: "review.calm.feel.level_2", defaultValue: "Hard", table: "Localizable", bundle: LorvexL10n.bundle)
    case 3: String(localized: "review.calm.feel.level_3", defaultValue: "Okay", table: "Localizable", bundle: LorvexL10n.bundle)
    case 4: String(localized: "review.calm.feel.level_4", defaultValue: "Good", table: "Localizable", bundle: LorvexL10n.bundle)
    default: feelHigh
    }
  }
  static var energyLabel: String { String(localized: "reviews.daily.energy", defaultValue: "Energy", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var energyLow: String { String(localized: "review.calm.energy.low", defaultValue: "Drained", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var energyHigh: String { String(localized: "review.calm.energy.high", defaultValue: "Full", table: "Localizable", bundle: LorvexL10n.bundle) }
  static func energyDot(_ level: Int) -> String {
    String(localized: "review.calm.energy.dot", defaultValue: "Energy \(level) of 5", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var movedLabel: String { String(localized: "review.calm.moved", defaultValue: "What moved forward", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var stillOpenLabel: String { String(localized: "review.calm.still_open", defaultValue: "Still open", table: "Localizable", bundle: LorvexL10n.bundle) }
  /// "2 more": the tasks a capped review list leaves out.
  /// The word for one energy level 1–5, named under the scale.
  static func energyWord(_ level: Int) -> String {
    switch level {
    case 1: energyLow
    case 2: String(localized: "review.calm.energy.level_2", defaultValue: "Low", table: "Localizable", bundle: LorvexL10n.bundle)
    case 3: String(localized: "review.calm.energy.level_3", defaultValue: "Steady", table: "Localizable", bundle: LorvexL10n.bundle)
    case 4: String(localized: "review.calm.energy.level_4", defaultValue: "Good", table: "Localizable", bundle: LorvexL10n.bundle)
    default: energyHigh
    }
  }
  static var habitsLabel: String { String(localized: "review.calm.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var checkIn: String { String(localized: "review.calm.check_in", defaultValue: "Check In", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var tomorrowLabel: String { String(localized: "review.calm.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var weekAheadLabel: String { String(localized: "review.calm.week_ahead", defaultValue: "The Week Ahead", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var weekAheadEmpty: String { String(localized: "review.calm.week_ahead.empty", defaultValue: "Nothing planned for the next seven days.", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var shapeLabel: String { String(localized: "review.calm.week_shape", defaultValue: "Finished each day", table: "Localizable", bundle: LorvexL10n.bundle) }
  /// "Monday, 2" for the week shape's VoiceOver sentence.
  static func shapeDay(_ weekday: String, _ count: Int) -> String {
    String(
      localized: "review.calm.week_shape.day", defaultValue: "\(weekday), \(count)",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var tomorrowEmpty: String { String(localized: "review.calm.tomorrow.empty", defaultValue: "Nothing planned yet.", table: "Localizable", bundle: LorvexL10n.bundle) }
  /// The still-open section's action over `count` tasks to move.
  static func moveSection(_ count: Int) -> String {
    count == 1
      ? moveRow
      : String(localized: "review.calm.move_all", defaultValue: "Move All to Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var moveRow: String { String(localized: "review.calm.move_one", defaultValue: "Move to Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle) }
  /// A still-open task's fact once it is planned for `plannedKey`, a day
  /// after the reviewed one: "Planned for tomorrow", or the day.
  static func plannedFact(_ plannedKey: String, tomorrowKey: String) -> String {
    if plannedKey == tomorrowKey {
      return String(localized: "review.calm.planned_tomorrow", defaultValue: "Planned for tomorrow", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    let day = plannedDayLabel(plannedKey)
    return String(localized: "review.calm.planned_day", defaultValue: "Planned for \(day)", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  private static func plannedDayLabel(_ key: String) -> String {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: key) else { return key }
    var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
    style.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return date.formatted(style)
  }
  static func moreCount(_ count: Int) -> String {
    String(localized: "review.more_count", defaultValue: "\(count) more", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var noteLabel: String { String(localized: "review.calm.note", defaultValue: "Note", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var notePrompt: String { String(localized: "review.calm.note.prompt", defaultValue: "Anything to remember?", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var moreFields: String { String(localized: "review.calm.more", defaultValue: "Wins, blockers, learnings", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var winsLabel: String { String(localized: "reviews.daily.wins", defaultValue: "Wins", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var winsPrompt: String { String(localized: "reviews.daily.wins_prompt", defaultValue: "Small ones count.", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var blockersLabel: String { String(localized: "reviews.daily.blockers", defaultValue: "Blockers", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var blockersPrompt: String { String(localized: "reviews.daily.blockers.placeholder", defaultValue: "What should be removed or clarified?", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var learningsLabel: String { String(localized: "reviews.daily.learnings", defaultValue: "Learnings", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var learningsPrompt: String { String(localized: "reviews.daily.learnings.placeholder", defaultValue: "What should tomorrow remember?", table: "Localizable", bundle: LorvexL10n.bundle) }

  // MARK: Week

  static func weekSentence(_ parts: [LorvexWeekReviewSentence.Part]) -> String {
    LorvexReviewSentence.join(parts.map(weekWord))
  }

  static func weekWord(_ part: LorvexWeekReviewSentence.Part) -> String {
    switch part {
    case .quiet:
      return String(localized: "review.week.quiet", defaultValue: "A quiet week.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .finished(let count):
      return String(localized: "review.week.finished", defaultValue: "You finished \(count) tasks.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .nothingFinished:
      return String(localized: "review.week.nothing_finished", defaultValue: "Nothing was finished.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .added(let count):
      return String(localized: "review.week.added", defaultValue: "\(count) new tasks came in.", table: "Localizable", bundle: LorvexL10n.bundle)
    case .overdue(let count):
      return String(localized: "review.week.overdue", defaultValue: "\(count) tasks are overdue.", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  static var daysLabel: String { String(localized: "review.week.days", defaultValue: "The days", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var pushedLabel: String { String(localized: "review.week.pushed", defaultValue: "Kept getting pushed", table: "Localizable", bundle: LorvexL10n.bundle) }
  static var overdueLabel: String { String(localized: "review.week.overdue_label", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle) }
  /// "Due 3 days ago" from a relative phrase.
  static func dueAgo(_ phrase: String) -> String {
    String(localized: "review.week.due_ago", defaultValue: "Due \(phrase)", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static func pushedCount(_ count: Int) -> String {
    String(localized: "review.week.pushed_count", defaultValue: "Pushed \(count) times", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static func someday(_ count: Int) -> String? {
    count == 0 ? nil : String(localized: "review.week.someday", defaultValue: "\(count) ideas wait in Someday.", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static func decisionTitle(_ task: ReviewTaskSummary) -> String {
    String(localized: "review.week.decision.title", defaultValue: "“\(task.title)” was pushed \(task.deferCount) times.", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var decisionMessage: String {
    String(localized: "review.week.decision.message", defaultValue: "Park it in Someday until it matters?", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var decisionAction: String {
    String(localized: "review.week.decision.action", defaultValue: "Move to Someday", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// "Mon, Sep 21".
  static func dayLabel(_ key: String) -> String {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: key) else { return key }
    var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
    style.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return date.formatted(style)
  }
}
