import Foundation
import SwiftUI

/// What a week's review sentence says, in order, before any wording. The macOS
/// and iPhone week reviews word the parts with their own copy tables.
public enum LorvexWeekReviewSentence {
  public enum Part: Equatable, Sendable {
    /// Nothing was finished, added, or left overdue.
    case quiet
    case finished(Int)
    case nothingFinished
    case added(Int)
    /// Open tasks now past their due date.
    case overdue(Int)
  }

  public static func parts(_ review: WeeklyReviewSnapshot) -> [Part] {
    if review.completedThisWeek == 0, review.createdThisWeek == 0, review.overdueOpen == 0 {
      return [.quiet]
    }
    var parts: [Part] = [review.completedThisWeek > 0 ? .finished(review.completedThisWeek) : .nothingFinished]
    if review.createdThisWeek > 0 { parts.append(.added(review.createdThisWeek)) }
    if review.overdueOpen > 0 { parts.append(.overdue(review.overdueOpen)) }
    return parts
  }

  /// The task a week review asks about: the one pushed off most often, once it
  /// has been pushed at least ``decisionThreshold`` times and is still open.
  public static func decisionTask(_ review: WeeklyReviewSnapshot) -> ReviewTaskSummary? {
    review.frequentlyDeferred
      .filter { $0.deferCount >= decisionThreshold && ($0.status == "open" || $0.status == "in_progress") }
      .max { $0.deferCount < $1.deferCount }
  }

  public static let decisionThreshold = 3

  /// The overdue tasks the page lists: all of them except the one the decision
  /// already asks about.
  public static func pastDue(_ review: WeeklyReviewSnapshot, decisionID: String?)
    -> [ReviewTaskSummary]
  {
    review.overdueTasks.filter { $0.id != decisionID }
  }

  /// The pushed tasks the page lists under "Kept getting pushed". Each task
  /// appears once on the page: the decision's task and the overdue ones are
  /// already shown above.
  public static func otherPushed(_ review: WeeklyReviewSnapshot, decisionID: String?)
    -> [ReviewTaskSummary]
  {
    let overdueIDs = Set(pastDue(review, decisionID: decisionID).map(\.id))
    return review.frequentlyDeferred.filter { $0.id != decisionID && !overdueIDs.contains($0.id) }
  }

  /// How long ago a due day was, in whole days counted from the day `now`
  /// falls on in `timeZone` ("yesterday", "3 days ago"). A named day comes
  /// from Foundation; a count of two or more days comes from LorvexCore's
  /// catalog, so Chinese writes it "3 天前" with the space every other count in
  /// the app carries. `nil` for a key that is not a `YYYY-MM-DD` day.
  public static func dueAgo(dayKey: String, now: Date, timeZone: TimeZone) -> String? {
    guard let due = LorvexDateFormatters.ymdUTC.date(from: dayKey) else { return nil }
    let days = PlannedDayBridge.dayOffset(from: now, toStorageDate: due, timeZone: timeZone)
    if days <= -2 {
      let count = -days
      return String(localized: "day_phrase.days_ago", defaultValue: "\(count) days ago", table: "Localizable", bundle: CoreL10n.bundle)
    }
    return LorvexDateFormatters.relativeDays(days)
  }
}

/// The week review on the calm page grammar, shared by macOS and iPhone: the
/// week, one serif sentence over a bar per day of what was finished, what
/// moved forward, the days that were written about (each opens its day), one
/// decision about the task that keeps getting
/// pushed, the overdue tasks, the other pushed tasks, the week ahead while the
/// review is of the current week, and one quiet line about Someday. Overdue and
/// pushed rows open their task through `openTask`, where
/// the user re-dates, finishes, or parks it. Each platform supplies the words
/// through ``Words``.
public struct LorvexWeekReviewPage: View {
  public struct Words {
    public var sentence: String
    public var movedLabel: String
    public var daysLabel: String
    public var pushedLabel: String
    /// The label over the overdue tasks.
    public var overdueLabel: String
    /// "Due 3 days ago" from a relative phrase such as "3 days ago".
    public var dueLine: (String) -> String
    /// "Mon, Sep 21" for a digest day key.
    public var dayLabel: (String) -> String
    /// "Pushed 4 times".
    public var pushedCount: (Int) -> String
    /// "2 more": the tasks of a capped list (finished, overdue) past the
    /// listed ones.
    public var moreLine: (Int) -> String
    /// "12 ideas wait in Someday."; `nil` when Someday is empty.
    public var somedayLine: String?
    public var decision: Decision?

    public init(
      sentence: String, movedLabel: String, daysLabel: String, pushedLabel: String,
      overdueLabel: String, dueLine: @escaping (String) -> String,
      dayLabel: @escaping (String) -> String, pushedCount: @escaping (Int) -> String,
      moreLine: @escaping (Int) -> String, somedayLine: String?, decision: Decision?
    ) {
      self.sentence = sentence
      self.movedLabel = movedLabel
      self.daysLabel = daysLabel
      self.pushedLabel = pushedLabel
      self.overdueLabel = overdueLabel
      self.dueLine = dueLine
      self.dayLabel = dayLabel
      self.pushedCount = pushedCount
      self.moreLine = moreLine
      self.somedayLine = somedayLine
      self.decision = decision
    }
  }

  public struct Decision {
    public var taskID: String
    public var title: String
    public var message: String
    public var actionTitle: String

    public init(taskID: String, title: String, message: String, actionTitle: String) {
      self.taskID = taskID
      self.title = title
      self.message = message
      self.actionTitle = actionTitle
    }
  }

  public var dateLine: String
  public var review: WeeklyReviewSnapshot
  public var days: [DailyReviewEntry]
  public var words: Words
  public var openDay: (String) -> Void
  public var openTask: (String) -> Void
  public var decide: (String) -> Void
  /// When set, the overdue and pushed rows lead with a circle that completes
  /// the task.
  public var completion: LorvexReviewTaskList.Completion?
  /// The seven days after today and their words; nil hides the section, as
  /// for a past week.
  public var weekAhead: (days: [LorvexAgendaDay], words: LorvexReviewWeekAhead.Words)?
  /// The finished count of each of the week's days, drawn under the sentence
  /// once anything was finished; nil while it loads.
  public var shape: (shape: LorvexWeekShape, words: LorvexWeekShapeStrip.Words)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.lorvexProductTimeZone) private var productTimeZone
  /// ``LorvexDesign/TextColumn/reviewDay`` scaled with the text.
  @ScaledMetric(relativeTo: .subheadline) private var dayColumnWidth = LorvexDesign.TextColumn.reviewDay
  /// 1 at the default text size; the mood dot grows with the day label.
  @ScaledMetric(relativeTo: .subheadline) private var moodDotScale: CGFloat = 1

  public init(
    dateLine: String, review: WeeklyReviewSnapshot, days: [DailyReviewEntry], words: Words,
    openDay: @escaping (String) -> Void, openTask: @escaping (String) -> Void,
    decide: @escaping (String) -> Void,
    completion: LorvexReviewTaskList.Completion? = nil,
    weekAhead: (days: [LorvexAgendaDay], words: LorvexReviewWeekAhead.Words)? = nil,
    shape: (shape: LorvexWeekShape, words: LorvexWeekShapeStrip.Words)? = nil
  ) {
    self.dateLine = dateLine
    self.review = review
    self.days = days
    self.words = words
    self.openDay = openDay
    self.openTask = openTask
    self.decide = decide
    self.completion = completion
    self.weekAhead = weekAhead
    self.shape = shape
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(dateLine)
          .font(LorvexDesign.Typography.pageLabel)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("review.week.date")
        Text(words.sentence, serifVoice: .pageSentence)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("review.week.headline")
        if let shape, shape.shape.peak > 0 {
          LorvexWeekShapeStrip(shape: shape.shape, words: shape.words)
            .padding(.top, LorvexDesign.Spacing.s)
        }
      }
      if !review.topCompleted.isEmpty {
        LorvexReviewMovedList(
          label: words.movedLabel, tasks: review.topCompleted,
          hiddenCount: review.hiddenCompletedCount, moreLine: words.moreLine,
          identifier: "review.week.moved")
      }
      if !sortedDays.isEmpty {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          LorvexPageLabel(words.daysLabel)
          ForEach(sortedDays, id: \.date) { entry in
            Button { openDay(entry.date) } label: { dayRow(entry) }
              .buttonStyle(.plain)
              .accessibilityIdentifier("review.week.day.\(entry.date)")
          }
        }
      }
      if let decision = words.decision {
        LorvexDecisionWell(
          title: decision.title, message: decision.message, actionTitle: decision.actionTitle,
          actionIdentifier: "review.week.decision", action: { decide(decision.taskID) })
      }
      if !pastDue.isEmpty {
        LorvexReviewTaskList(
          label: words.overdueLabel, tasks: pastDue,
          // The snapshot lists the earliest few; the sentence counts them all.
          hiddenCount: max(0, review.overdueOpen - review.overdueTasks.count),
          moreLine: words.moreLine, identifier: "review.week.overdue", detail: dueDetail,
          completion: completion, openTask: openTask)
      }
      if !otherPushed.isEmpty {
        LorvexReviewTaskList(
          label: words.pushedLabel, tasks: otherPushed, hiddenCount: 0,
          moreLine: words.moreLine, identifier: "review.week.pushed",
          detail: { words.pushedCount($0.deferCount) }, completion: completion,
          openTask: openTask)
      }
      if let weekAhead {
        LorvexReviewWeekAhead(
          days: weekAhead.days, words: weekAhead.words, identifier: "review.week.ahead", openTask: openTask)
      }
      if let somedayLine = words.somedayLine {
        Text(somedayLine)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("review.week.someday")
      }
    }
  }

  private var sortedDays: [DailyReviewEntry] { days.sorted { $0.date < $1.date } }

  private var pastDue: [ReviewTaskSummary] {
    LorvexWeekReviewSentence.pastDue(review, decisionID: words.decision?.taskID)
  }

  private var otherPushed: [ReviewTaskSummary] {
    LorvexWeekReviewSentence.otherPushed(review, decisionID: words.decision?.taskID)
  }

  /// "Due 3 days ago", counted from today in the product time zone and
  /// measured from the preview clock when a capture pins it.
  private func dueDetail(_ task: ReviewTaskSummary) -> String? {
    guard let dueDate = task.dueDate,
      let ago = LorvexWeekReviewSentence.dueAgo(
        dayKey: dueDate, now: LorvexPreviewClock.now(in: .current), timeZone: productTimeZone)
    else { return nil }
    return words.dueLine(ago)
  }

  /// The day, a dot sized by how the day felt (empty when no rating was
  /// given), and the note written in that day's review. The day sits in a
  /// column beside the note, or above it from `.xxLarge` up
  /// (``SwiftUI/DynamicTypeSize/stacksTimeColumn``), where the column would
  /// leave the note a few words a line; the note keeps to two lines, and
  /// shows whole at the accessibility sizes.
  private func dayRow(_ entry: DailyReviewEntry) -> some View {
    Group {
      if dynamicTypeSize.stacksTimeColumn {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
            dayLabel(entry)
            moodDot(entry)
          }
          daySummary(entry)
            .lineLimitUnlessAccessibilitySize(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          dayLabel(entry)
            .frame(minWidth: dayColumnWidth, alignment: .leading)
          moodDot(entry)
          daySummary(entry)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .contentShape(Rectangle())
  }

  private func dayLabel(_ entry: DailyReviewEntry) -> some View {
    Text(words.dayLabel(entry.date))
      .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
      .foregroundStyle(.secondary)
  }

  /// The dot's size, its column and its drop below the label's center all
  /// scale with the label, so the dot stays level with the label's lowercase
  /// letters at every text size.
  private func moodDot(_ entry: DailyReviewEntry) -> some View {
    let scale = moodDotScale
    let size = (4 + CGFloat(entry.mood ?? 0) * 2) * scale
    return Circle()
      .fill(LorvexDesign.Palette.accent.opacity(entry.mood == nil ? 0 : 1))
      .frame(width: size, height: size)
      .frame(width: 16 * scale, height: 12 * scale)
      .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 * scale }
      .accessibilityHidden(true)
  }

  private func daySummary(_ entry: DailyReviewEntry) -> some View {
    Text(entry.summary, serifVoice: .assistantSecondary)
      .userContentTypesetting(entry.summary)
      .foregroundStyle(.primary)
  }
}
