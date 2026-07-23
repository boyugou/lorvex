import LorvexCore
import SwiftUI

/// The persistent right-hand column of the Reviews surface: objective data that
/// sits beside the human reflection. In Day scope it shows the selected day's
/// activity counts (``DayReviewSummary``); in Week scope it shows the week's
/// throughput metrics, estimate coverage, and deferral insights relocated from
/// the old center pane.
struct ReviewEvidencePanel: View {
  enum Content: Equatable {
    case day(DayReviewSummary?)
    case week(WeeklyReviewSnapshot?)
  }

  let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        switch content {
        case let .day(summary):
          ReviewDayEvidence(summary: summary)
        case let .week(review):
          ReviewWeekEvidence(review: review)
        }
      }
      .padding(LorvexDesign.Spacing.l)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityIdentifier("reviews.evidence.panel")
  }
}

/// The Day-scope evidence body: a titled panel of metric rows and the day's top
/// completed task titles.
private struct ReviewDayEvidence: View {
  let summary: DayReviewSummary?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Text(LocalizedStringResource("reviews.evidence.day_title", defaultValue: "This day", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.sectionHeader)

      if let summary, hasActivity(summary) {
        VStack(spacing: LorvexDesign.Spacing.s) {
          ReviewEvidenceRow(
            title: String(localized: "reviews.day.evidence.completed", defaultValue: "Completed", table: "Localizable", bundle: LorvexL10n.bundle),
            value: summary.completedCount,
            systemImage: "checkmark.circle.fill",
            tint: .green
          )
          ReviewEvidenceRow(
            title: String(localized: "reviews.day.evidence.due_open", defaultValue: "Unfinished", table: "Localizable", bundle: LorvexL10n.bundle),
            value: summary.dueOpenCount,
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange
          )
          ReviewEvidenceRow(
            title: String(localized: "reviews.day.evidence.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle),
            value: summary.habitsCompleted,
            total: summary.habitsTotal,
            systemImage: "circle.lefthalf.filled",
            tint: .blue
          )
          ReviewEvidenceRow(
            title: String(localized: "reviews.day.evidence.events", defaultValue: "Events", table: "Localizable", bundle: LorvexL10n.bundle),
            value: summary.eventCount,
            systemImage: "calendar",
            tint: .purple
          )
          ReviewEvidenceRow(
            title: String(localized: "reviews.day.evidence.created", defaultValue: "Created", table: "Localizable", bundle: LorvexL10n.bundle),
            value: summary.createdCount,
            systemImage: "plus.circle.fill",
            tint: .secondary,
            isSecondary: true
          )
        }

        if !summary.topCompleted.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(summary.topCompleted) { task in
              ReviewTaskRow(task: task, systemImage: "checkmark.circle.fill")
                .padding(.vertical, LorvexDesign.Spacing.xs)
              if task.id != summary.topCompleted.last?.id {
                Divider()
              }
            }
          }
          .padding(LorvexDesign.Spacing.m)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.06), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
        }
      } else {
        LorvexEmptyStatePanel(
          title: String(localized: "reviews.day.evidence.empty.title", defaultValue: "No activity", table: "Localizable", bundle: LorvexL10n.bundle),
          message: String(localized: "reviews.day.evidence.empty", defaultValue: "No activity recorded for this day.", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "calendar.badge.clock",
          tint: .secondary,
          style: .inline
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func hasActivity(_ summary: DayReviewSummary) -> Bool {
    summary.completedCount > 0 || summary.dueOpenCount > 0 || summary.habitsTotal > 0
      || summary.eventCount > 0 || summary.createdCount > 0
  }
}

/// The Week-scope evidence body: the five throughput metric cards, the estimate
/// coverage row, and the completed / frequently-deferred insight lists.
private struct ReviewWeekEvidence: View {
  let review: WeeklyReviewSnapshot?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Text(LocalizedStringResource("reviews.evidence.week_title", defaultValue: "This week", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.sectionHeader)

      if let review {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 112), spacing: LorvexDesign.Spacing.s)],
          spacing: LorvexDesign.Spacing.s
        ) {
          ReviewMetricCard(
            title: String(localized: "reviews.weekly.completed", defaultValue: "Completed", table: "Localizable", bundle: LorvexL10n.bundle),
            metricKey: "completed",
            value: review.completedThisWeek,
            systemImage: "checkmark.circle.fill",
            tint: .green
          )
          ReviewMetricCard(
            title: String(localized: "reviews.weekly.created", defaultValue: "Created", table: "Localizable", bundle: LorvexL10n.bundle),
            metricKey: "created",
            value: review.createdThisWeek,
            systemImage: "plus.circle.fill",
            tint: .blue
          )
          ReviewMetricCard(
            title: String(localized: "reviews.weekly.overdue", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle),
            metricKey: "overdue",
            value: review.overdueOpen,
            systemImage: "exclamationmark.triangle.fill",
            tint: .red
          )
          ReviewMetricCard(
            title: String(localized: "reviews.weekly.deferred", defaultValue: "Deferred", table: "Localizable", bundle: LorvexL10n.bundle),
            metricKey: "deferred",
            value: review.deferredOpen,
            systemImage: "clock.fill",
            tint: .orange
          )
          ReviewMetricCard(
            title: String(localized: "reviews.weekly.someday", defaultValue: "Someday", table: "Localizable", bundle: LorvexL10n.bundle),
            metricKey: "someday",
            value: review.someday,
            systemImage: "tray.fill",
            tint: .gray
          )
        }
        .accessibilityIdentifier("weeklyReview.metrics")

        if let estimateCoverageRatio = review.estimateCoverageRatio {
          EstimateCoverageRow(value: estimateCoverageRatio)
        }

        ReviewInsightSection(
          title: String(localized: "reviews.weekly.completed", defaultValue: "Completed", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "checkmark.circle.fill",
          tint: .green,
          tasks: review.topCompleted
        )

        ReviewInsightSection(
          title: String(
            localized:
              "reviews.weekly.frequently_deferred",
              defaultValue: "Frequently Deferred",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
          systemImage: "clock",
          tint: .orange,
          tasks: review.frequentlyDeferred
        )

        ReviewInsightSection(
          title: String(
            localized:
              "reviews.weekly.someday_section",
              defaultValue: "Someday",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
          systemImage: "tray",
          tint: .gray,
          tasks: review.topSomeday
        )
      } else {
        weeklyReviewEmptyState
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var weeklyReviewEmptyState: some View {
    LorvexEmptyStatePanel(
      title: String(localized: "reviews.weekly.empty.title", defaultValue: "No Weekly Review", table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "reviews.weekly.empty.description",
        defaultValue: "Weekly patterns appear after Lorvex has enough recent task activity to summarize.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "text.badge.checkmark",
      tint: .accentColor,
      chips: [
        LorvexEmptyStateChip(
          title: String(localized: "reviews.weekly.empty.chip", defaultValue: "Reflect", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "sparkles",
          tint: .accentColor
        )
      ]
    )
  }
}

/// A compact label / value metric row for the Day evidence panel. `total`, when
/// set, renders as "value / total" for the habits ratio.
private struct ReviewEvidenceRow: View {
  let title: String
  let value: Int
  var total: Int? = nil
  let systemImage: String
  let tint: Color
  var isSecondary = false

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: systemImage)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
        .frame(width: 18)
      Text(title)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(isSecondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      Spacer(minLength: LorvexDesign.Spacing.s)
      Text(valueText)
        .font(LorvexDesign.Typography.secondaryText.monospacedDigit().weight(.semibold))
        .foregroundStyle(isSecondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .contentTransition(.numericText())
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .background(.quaternary.opacity(0.06), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(lorvexPairLabel(title, valueText))
  }

  private var valueText: String {
    if let total {
      return "\(value) / \(total)"
    }
    return "\(value)"
  }
}

/// The week-throughput estimate-coverage ratio row, relocated into the evidence
/// panel.
private struct EstimateCoverageRow: View {
  let value: Double

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "timer")
        .foregroundStyle(Color.accentColor)
      Text(LocalizedStringResource(
        "reviews.weekly.estimate_coverage",
        defaultValue: "Estimate Coverage",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .font(LorvexDesign.Typography.secondaryText)
      Spacer()
      Text(value, format: .percent.precision(.fractionLength(0)))
        .font(LorvexDesign.Typography.secondaryText.monospacedDigit().weight(.semibold))
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
  }
}

/// A titled list of review task summaries (completed, frequently-deferred),
/// hidden when empty so the panel never shows a bare header.
private struct ReviewInsightSection: View {
  let title: String
  let systemImage: String
  let tint: Color
  let tasks: [ReviewTaskSummary]

  var body: some View {
    if !tasks.isEmpty {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        Label(title, systemImage: systemImage)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(tint)

        VStack(spacing: 0) {
          ForEach(tasks) { task in
            ReviewTaskRow(task: task, systemImage: systemImage)
            if task.id != tasks.last?.id {
              Divider()
            }
          }
        }
      }
      .padding(LorvexDesign.Spacing.m)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
      .overlay {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.m)
          .stroke(.separator.opacity(0.35), lineWidth: 1)
      }
    }
  }
}
