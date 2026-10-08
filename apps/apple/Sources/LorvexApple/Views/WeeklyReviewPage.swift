import LorvexCore
import SwiftUI

/// The macOS week review: the shared calm week page in a readable column. A
/// day opens in the Day scope through `openDay`; an overdue or pushed task's
/// circle completes it (⌘Z reopens it) and its title opens it in Tasks with
/// its inspector; the decision parks the task that keeps getting pushed in
/// Someday. Under the week's sentence, a bar per day shows how many tasks
/// were finished; while the review is of the current week, the page closes on
/// the seven days ahead.
struct WeeklyReviewPage: View {
  @Bindable var store: AppStore
  let openDay: (String) -> Void
  @Environment(\.undoManager) private var undoManager
  @State private var weekAhead: [LorvexAgendaDay]?
  @State private var shape: LorvexWeekShape?

  private typealias Copy = ReviewCalmCopy

  var body: some View {
    ScrollView {
      Group {
        if let review = store.weeklyReview {
          LorvexWeekReviewPage(
            dateLine: review.windowRangeLabel(),
            review: review,
            days: store.weekReviewDigest,
            words: Self.words(review),
            openDay: openDay,
            openTask: { id in
              store.selection = .tasks
              store.selectedTaskID = id
            },
            decide: { id in Task { await store.parkReviewTaskInSomeday(id) } },
            completion: .init(label: TaskDisplayText.completionToggle(isDone: false)) { id in
              await store.completeTask(id: id, undoManager: undoManager)
            },
            weekAhead: store.isViewingCurrentWeek ? weekAhead.map { ($0, Self.weekAheadWords) } : nil,
            shape: shape.map { ($0, Self.shapeWords) })
        } else {
          LorvexEmptyStatePanel(
            title: String(localized: "reviews.weekly.empty.title", defaultValue: "No review yet", table: "Localizable", bundle: LorvexL10n.bundle),
            message: String(localized: "reviews.weekly.empty.message", defaultValue: "The week appears here once Lorvex has task activity to summarize.", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "text.badge.checkmark",
            tint: .secondary,
            style: .inline)
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.xl)
      .padding(.vertical, LorvexDesign.Spacing.l)
      .frame(maxWidth: 680, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(.background)
    .accessibilityIdentifier("reviews.weekly")
    .task(id: store.weekReviewReadKey) {
      if let loaded = await store.loadWeekShape() { shape = loaded }
      guard store.isViewingCurrentWeek else { return }
      if let loaded = await store.loadWeekAheadAgenda() { weekAhead = loaded }
    }
  }

  static var shapeWords: LorvexWeekShapeStrip.Words {
    LorvexWeekShapeStrip.Words(label: Copy.shapeLabel, dayCount: Copy.shapeDay)
  }

  static var weekAheadWords: LorvexReviewWeekAhead.Words {
    LorvexReviewWeekAhead.Words(
      label: Copy.weekAheadLabel, emptyLine: Copy.weekAheadEmpty, allDay: TodayCalmCopy.allDay,
      dayLabel: Copy.dayLabel, moreLine: Copy.moreCount, timeRange: TodayCalmCopy.timeRange(start:end:))
  }

  static func words(_ review: WeeklyReviewSnapshot) -> LorvexWeekReviewPage.Words {
    let decision = LorvexWeekReviewSentence.decisionTask(review).map { task in
      LorvexWeekReviewPage.Decision(
        taskID: task.id, title: Copy.decisionTitle(task), message: Copy.decisionMessage,
        actionTitle: Copy.decisionAction)
    }
    return LorvexWeekReviewPage.Words(
      sentence: Copy.weekSentence(LorvexWeekReviewSentence.parts(review)),
      movedLabel: Copy.movedLabel,
      daysLabel: Copy.daysLabel,
      pushedLabel: Copy.pushedLabel,
      overdueLabel: Copy.overdueLabel,
      dueLine: Copy.dueAgo,
      dayLabel: Copy.dayLabel,
      pushedCount: Copy.pushedCount,
      moreLine: Copy.moreCount,
      somedayLine: Copy.someday(review.someday),
      decision: decision)
  }
}
