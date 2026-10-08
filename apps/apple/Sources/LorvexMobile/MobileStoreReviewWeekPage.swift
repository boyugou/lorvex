import LorvexCore
import SwiftUI

/// The iPhone week review: the shared calm week page in a readable column, or
/// a quiet note while the week has nothing to summarize. A day opens in the
/// Day scope through `openDay`; an overdue or pushed task pushes its detail
/// onto the Review stack. Under the week's sentence, a bar per day shows how
/// many tasks were finished; while the review is of the current week, the
/// page closes on the seven days ahead.
struct MobileStoreReviewWeekPage: View {
  @Bindable var store: MobileStore
  let openDay: (String) -> Void
  @State private var weekAhead: [LorvexAgendaDay]?
  @State private var shape: LorvexWeekShape?

  private typealias Copy = MobileReviewCalmCopy

  var body: some View {
    ScrollView {
      Group {
        if let review = store.snapshot.weeklyReview {
          LorvexWeekReviewPage(
            dateLine: review.windowRangeLabel(),
            review: review,
            days: store.weekReviewDigest,
            words: words(review),
            openDay: openDay,
            openTask: { id in store.openTaskRouteOnCurrentStack(id) },
            decide: { id in Task { await store.parkReviewTaskInSomeday(id) } },
            completion: .init(label: MobileTaskActionCopy.completionToggle(isDone: false)) { id in
              await store.completeTask(id)
            },
            weekAhead: store.weeklyReviewAnchor == nil ? weekAhead.map { ($0, weekAheadWords) } : nil,
            shape: shape.map { ($0, shapeWords) })
        } else {
          MobileEmptyState(
            icon: "chart.line.uptrend.xyaxis",
            tint: LorvexDesign.Palette.Destination.review,
            title: String(
              localized: "review.empty.not_loaded", defaultValue: "No Review Loaded",
              table: "Localizable", bundle: MobileL10n.bundle),
            message: String(
              localized: "review.empty.not_loaded.message",
              defaultValue:
                "Weekly patterns appear after Lorvex has enough recent task activity to summarize.",
              table: "Localizable", bundle: MobileL10n.bundle))
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.l)
      .padding(.top, LorvexDesign.Spacing.s)
      .padding(.bottom, LorvexDesign.Spacing.xl)
      .frame(maxWidth: 640, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .refreshable { await store.refresh() }
    .mobileReviewScrollAnchor()
    .accessibilityIdentifier("review.week")
    .task(id: store.weekReviewReadKey) {
      if let loaded = await store.loadWeekShape() { shape = loaded }
      guard store.weeklyReviewAnchor == nil else { return }
      if let loaded = await store.loadWeekAheadAgenda() { weekAhead = loaded }
    }
  }

  private var shapeWords: LorvexWeekShapeStrip.Words {
    LorvexWeekShapeStrip.Words(label: Copy.shapeLabel, dayCount: Copy.shapeDay)
  }

  private var weekAheadWords: LorvexReviewWeekAhead.Words {
    LorvexReviewWeekAhead.Words(
      label: Copy.weekAheadLabel, emptyLine: Copy.weekAheadEmpty, allDay: Copy.allDay,
      dayLabel: Copy.dayLabel, moreLine: Copy.moreCount, timeRange: MobileTodayCalmCopy.timeRange(start:end:))
  }

  private func words(_ review: WeeklyReviewSnapshot) -> LorvexWeekReviewPage.Words {
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
