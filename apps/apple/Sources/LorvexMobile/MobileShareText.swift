import Foundation
import LorvexCore

/// The text the share sheet sends for a task or a review: plain lines in the
/// user's language that read the same in Messages, Mail, Notes, or a Markdown
/// editor, worded as the screen words them. Blocks are separated by a blank
/// line, a section is its name on one line with its content below, and a list
/// item starts with "- ". Days are written as dates rather than "tomorrow",
/// since the text is read after the day it was shared on.
enum MobileShareText {
  /// The task in the order its detail shows it: the title, the status when the
  /// task is not open, the notes, one "Label: value" line per set field, the
  /// assistant context, and the checklist (`- [x]` for a finished item).
  static func task(_ task: LorvexTask, listName: String?, logicalDay: String) -> String {
    var blocks: [String] = []
    blocks.append(
      task.status == .open ? task.title : "\(task.title)\n\(task.status.localizedName)")
    if let notes = nonBlank(task.notes) { blocks.append(notes) }
    let rows = MobileTaskProperties(task: task, listName: listName, logicalDay: logicalDay, days: .dated).rows
    if !rows.isEmpty {
      blocks.append(rows.map { field(MobileTaskPropertyCopy.label($0.field), $0.value) }.joined(separator: "\n"))
    }
    if let aiNotes = nonBlank(task.aiNotes) {
      blocks.append(section(MobileTaskPropertyCopy.assistantContext, aiNotes))
    }
    if !task.checklistItems.isEmpty {
      let items = task.checklistItems.sorted { $0.position < $1.position }
        .map { "- [\($0.completedAt == nil ? " " : "x")] \($0.text)" }
      blocks.append(section(MobileTaskPropertyCopy.checklist, items.joined(separator: "\n")))
    }
    return blocks.joined(separator: "\n\n")
  }

  /// The day's review: its date, how it felt and the energy it had ("Feeling
  /// 4 of 5 · Energy 3 of 5"), then the note, wins, blockers, and learnings
  /// that were written.
  static func dailyReview(_ review: DailyReviewEntry) -> String {
    typealias Copy = MobileReviewCalmCopy
    let day =
      LorvexDateFormatters.ymdUTC.date(from: review.date).map {
        LorvexDateFormatters.string($0, dateStyle: .full, timeZone: .gmt)
      } ?? review.date
    var blocks = [
      String(
        localized: "review.share.daily_title", defaultValue: "Daily Review — \(day)", table: "Localizable",
        bundle: MobileL10n.bundle)
    ]
    let scales = [review.mood.map(Copy.feelDot), review.energyLevel.map(Copy.energyDot)].compactMap { $0 }
    if !scales.isEmpty { blocks.append(scales.joined(separator: " · ")) }
    for (label, text) in [
      (Copy.noteLabel, review.summary), (Copy.winsLabel, review.wins ?? ""),
      (Copy.blockersLabel, review.blockers ?? ""), (Copy.learningsLabel, review.learnings ?? ""),
    ] {
      if let text = nonBlank(text) { blocks.append(section(label, text)) }
    }
    return blocks.joined(separator: "\n\n")
  }

  /// The week's review as its page reads: the week, the sentence about it,
  /// what moved forward, the overdue tasks, the other tasks that kept getting
  /// pushed with how often, and the line about Someday. Each task is listed
  /// once, under the first section that names it.
  static func weeklyReview(_ review: WeeklyReviewSnapshot) -> String {
    typealias Copy = MobileReviewCalmCopy
    let range = review.windowRangeLabel(includesYear: true)
    var blocks = [
      String(
        localized: "review.share.weekly_title", defaultValue: "Weekly Review — \(range)", table: "Localizable",
        bundle: MobileL10n.bundle),
      Copy.weekSentence(LorvexWeekReviewSentence.parts(review)),
    ]
    func list(_ label: String, _ items: [String]) {
      guard !items.isEmpty else { return }
      blocks.append(section(label, items.map { "- \($0)" }.joined(separator: "\n")))
    }
    list(Copy.movedLabel, review.topCompleted.map(\.title))
    list(Copy.overdueLabel, LorvexWeekReviewSentence.pastDue(review, decisionID: nil).map(\.title))
    list(
      Copy.pushedLabel,
      LorvexWeekReviewSentence.otherPushed(review, decisionID: nil).map {
        item($0.title, detail: Copy.pushedCount($0.deferCount))
      })
    if let someday = Copy.someday(review.someday) { blocks.append(someday) }
    return blocks.joined(separator: "\n\n")
  }

  /// "Due: Tue, Sep 29, 2026": a field's name and value on one line, with the
  /// punctuation the language puts between them.
  private static func field(_ label: String, _ value: String) -> String {
    String(
      localized: "share.field", defaultValue: "\(label): \(value)", table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// "Big refactor (Pushed 4 times)": a listed task with one fact about it.
  private static func item(_ title: String, detail: String) -> String {
    String(
      localized: "share.item_detail", defaultValue: "\(title) (\(detail))", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  private static func section(_ label: String, _ body: String) -> String {
    "\(label)\n\(body)"
  }

  private static func nonBlank(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }
}
