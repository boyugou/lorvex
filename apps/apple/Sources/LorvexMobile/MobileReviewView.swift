import Foundation
import LorvexCore
import SwiftUI

struct MobileReviewMetricsGrid: View {
  let review: WeeklyReviewSnapshot

  var body: some View {
    Section(review.windowTitle) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
        MobileReviewMetricCard(
          title: String(
            localized: "review.completed", defaultValue: "Completed", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: review.completedThisWeek,
          systemImage: "checkmark.circle.fill",
          tint: .green
        )
        MobileReviewMetricCard(
          title: String(
            localized: "review.created", defaultValue: "Created", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: review.createdThisWeek,
          systemImage: "plus.circle.fill",
          tint: .blue
        )
        MobileReviewMetricCard(
          title: String(
            localized: "review.overdue", defaultValue: "Overdue", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: review.overdueOpen,
          systemImage: "exclamationmark.triangle.fill",
          tint: .red
        )
        MobileReviewMetricCard(
          title: String(
            localized: "review.deferred", defaultValue: "Deferred", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: review.deferredOpen,
          systemImage: "clock.fill",
          tint: .orange
        )
        MobileReviewMetricCard(
          title: String(
            localized: "review.someday", defaultValue: "Someday", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: review.someday,
          systemImage: "tray.fill",
          tint: .gray
        )
      }
      .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

      if let estimateCoverageRatio = review.estimateCoverageRatio {
        LabeledContent(
          String(
            localized: "review.estimate_coverage", defaultValue: "Estimate Coverage",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          Text(estimateCoverageRatio, format: .percent.precision(.fractionLength(0)))
            .monospacedDigit()
        }
        .accessibilityIdentifier("review.weekly.estimateCoverage")
      }
    }
  }
}

struct MobileReviewMetricCard: View {
  let title: String
  let value: Int
  let systemImage: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: systemImage)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
        .font(LorvexDesign.Typography.sectionHeader)
      Text(value, format: .number)
        .font(LorvexDesign.Typography.sectionHeader.monospacedDigit())
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      String(
        format: String(
          localized: "review.metric.a11y", defaultValue: "%@: %lld", table: "Localizable",
          bundle: MobileL10n.bundle), title, value))
  }
}

struct MobileReviewDayEvidenceSection: View {
  let summary: DayReviewSummary?

  var body: some View {
    Section(
      String(
        localized: "review.evidence.day_title", defaultValue: "This Day", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      if let summary, hasActivity(summary) {
        MobileReviewEvidenceRow(
          title: String(
            localized: "review.evidence.completed", defaultValue: "Completed", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: summary.completedCount,
          systemImage: "checkmark.circle.fill",
          tint: .green
        )
        MobileReviewEvidenceRow(
          title: String(
            localized: "review.evidence.unfinished", defaultValue: "Unfinished",
            table: "Localizable", bundle: MobileL10n.bundle),
          value: summary.dueOpenCount,
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange
        )
        MobileReviewEvidenceRow(
          title: String(
            localized: "review.evidence.habits", defaultValue: "Habits", table: "Localizable",
            bundle: MobileL10n.bundle),
          valueText: "\(summary.habitsCompleted) / \(summary.habitsTotal)",
          systemImage: "circle.lefthalf.filled",
          tint: .blue
        )
        MobileReviewEvidenceRow(
          title: String(
            localized: "review.evidence.events", defaultValue: "Events", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: summary.eventCount,
          systemImage: "calendar",
          tint: .purple
        )
        MobileReviewEvidenceRow(
          title: String(
            localized: "review.evidence.created", defaultValue: "Created", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: summary.createdCount,
          systemImage: "plus.circle.fill",
          tint: .secondary
        )
        if !summary.topCompleted.isEmpty {
          ForEach(summary.topCompleted) { task in
            MobileReviewTaskRow(task: task, systemImage: "checkmark.circle.fill")
          }
        }
      } else {
        ContentUnavailableView(
          String(
            localized: "review.evidence.empty.title", defaultValue: "No Activity",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "chart.bar.doc.horizontal",
          description: Text(
            String(
              localized: "review.evidence.empty.message",
              defaultValue:
                "No completed tasks, open due items, habits, events, or created tasks are recorded for this day.",
              table: "Localizable", bundle: MobileL10n.bundle))
        )
      }
    }
  }

  private func hasActivity(_ summary: DayReviewSummary) -> Bool {
    summary.completedCount > 0 || summary.dueOpenCount > 0 || summary.habitsTotal > 0
      || summary.eventCount > 0 || summary.createdCount > 0
  }
}

private struct MobileReviewEvidenceRow: View {
  let title: String
  let valueText: String
  let systemImage: String
  let tint: Color

  init(title: String, value: Int, systemImage: String, tint: Color) {
    self.title = title
    self.valueText = "\(value)"
    self.systemImage = systemImage
    self.tint = tint
  }

  init(title: String, valueText: String, systemImage: String, tint: Color) {
    self.title = title
    self.valueText = valueText
    self.systemImage = systemImage
    self.tint = tint
  }

  var body: some View {
    LabeledContent {
      Text(valueText)
        .monospacedDigit()
        .fontWeight(.semibold)
    } label: {
      Label(title, systemImage: systemImage)
        .foregroundStyle(tint)
    }
    .accessibilityElement(children: .combine)
  }
}

struct MobileReviewDigestSection: View {
  let reviews: [DailyReviewEntry]
  let onSelectDay: (String) -> Void

  var body: some View {
    Section(
      String(
        localized: "review.digest.title", defaultValue: "This Week's Reviews", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      if sortedReviews.isEmpty {
        ContentUnavailableView(
          String(
            localized: "review.digest.empty.title", defaultValue: "No Daily Reviews",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "text.badge.checkmark",
          description: Text(
            String(
              localized: "review.digest.empty.message",
              defaultValue: "Daily reviews written in this weekly window will appear here.",
              table: "Localizable", bundle: MobileL10n.bundle))
        )
      } else {
        ForEach(sortedReviews, id: \.date) { review in
          Button {
            onSelectDay(review.date)
          } label: {
            MobileReviewDigestRow(review: review)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("review.weekly.digest.day\(review.date.replacingOccurrences(of: "-", with: ""))")
        }
      }
    }
  }

  private var sortedReviews: [DailyReviewEntry] {
    reviews.sorted { $0.date > $1.date }
  }
}

private struct MobileReviewDigestRow: View {
  let review: DailyReviewEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(formattedDate)
          .font(LorvexDesign.Typography.primaryEmphasis)
        Spacer()
        if let mood = review.mood {
          scoreBadge(
            systemImage: "heart.fill", tint: .pink, value: mood,
            accessibilityName: String(
              localized: "review.field.mood", defaultValue: "Mood", table: "Localizable",
              bundle: MobileL10n.bundle))
        }
        if let energy = review.energyLevel {
          scoreBadge(
            systemImage: "bolt.fill", tint: .orange, value: energy,
            accessibilityName: String(
              localized: "review.field.energy", defaultValue: "Energy", table: "Localizable",
              bundle: MobileL10n.bundle))
        }
      }
      if !review.summary.isEmpty {
        Text(review.summary)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var formattedDate: String {
    if let date = LorvexDateFormatters.ymd.date(from: review.date) {
      return date.formatted(.dateTime.weekday(.wide).month().day())
    }
    return review.date
  }

  private func scoreBadge(
    systemImage: String, tint: Color, value: Int, accessibilityName: String
  ) -> some View {
    Label("\(value)", systemImage: systemImage)
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .foregroundStyle(tint)
      .labelStyle(.titleAndIcon)
      .monospacedDigit()
      .accessibilityLabel(
        String(
          format: String(
            localized: "review.metric.a11y", defaultValue: "%@: %lld", table: "Localizable",
            bundle: MobileL10n.bundle), accessibilityName, value))
  }
}

struct MobileWeeklyReviewSection: View {
  let review: WeeklyReviewSnapshot

  var body: some View {
    MobileReviewMetricsGrid(review: review)
    MobileReviewTaskListSection(
      title: String(
        localized: "review.section.completed", defaultValue: "Completed", table: "Localizable",
        bundle: MobileL10n.bundle),
      tasks: review.topCompleted,
      systemImage: "checkmark.circle.fill"
    )
    MobileReviewTaskListSection(
      title: String(
        localized: "review.section.frequently_deferred", defaultValue: "Frequently Deferred",
        table: "Localizable", bundle: MobileL10n.bundle),
      tasks: review.frequentlyDeferred,
      systemImage: "clock"
    )
    MobileReviewTaskListSection(
      title: String(
        localized: "review.section.someday", defaultValue: "Someday", table: "Localizable",
        bundle: MobileL10n.bundle),
      tasks: review.topSomeday,
      systemImage: "tray"
    )
  }
}

private struct MobileReviewTaskListSection: View {
  let title: String
  let tasks: [ReviewTaskSummary]
  let systemImage: String

  var body: some View {
    if !tasks.isEmpty {
      Section(title) {
        ForEach(tasks) { task in
          MobileReviewTaskRow(task: task, systemImage: systemImage)
        }
      }
    }
  }
}

struct MobileReviewTaskRow: View {
  let task: ReviewTaskSummary
  let systemImage: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text(task.title)
          .lineLimit(2)
        Text(MobileReviewTaskRowText.subtitle(for: task))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("review.task.\(task.id)")
  }
}

enum MobileReviewTaskRowText {
  static func subtitle(for task: ReviewTaskSummary) -> String {
    let status = localizedStatus(task.status)
    guard task.deferCount > 0 else { return status }
    return String(
      localized: "review.task.deferred_count",
      defaultValue: "\(status) · deferred \(task.deferCount) times",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private static func localizedStatus(_ rawStatus: String) -> String {
    guard let status = LorvexTask.Status(rawValue: rawStatus) else { return rawStatus }
    return MobileTaskDisplayText.status(status)
  }
}
