import LorvexCore
import SwiftUI

/// The saved review of a past day outside the write window, in the calm page
/// grammar: the two ratings on disabled dot scales and each written field under
/// its name, or an empty-state note when nothing was written that day. The
/// page header above it names the day and reads the day's sentence.
struct DailyReviewReadOnlyView: View {
  let review: DailyReviewEntry?

  private typealias Copy = ReviewCalmCopy

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
      if let review, !isEmptyReview(review) {
        if review.mood != nil || review.energyLevel != nil {
          HStack(alignment: .top, spacing: LorvexDesign.Spacing.xl) {
            scale(
              Copy.feelLabel, value: review.mood, low: Copy.feelLow, high: Copy.feelHigh, dotLabel: Copy.feelDot,
              identifier: "reviews.readonly.mood")
            scale(
              Copy.energyLabel, value: review.energyLevel, low: Copy.energyLow, high: Copy.energyHigh,
              dotLabel: Copy.energyDot, identifier: "reviews.readonly.energy")
          }
        }
        written(Copy.noteLabel, review.summary)
        written(Copy.winsLabel, review.wins)
        written(Copy.blockersLabel, review.blockers)
        written(Copy.learningsLabel, review.learnings)

        Label(
          String(localized: "reviews.daily.readonly_note", defaultValue: "Older reviews are read-only.", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "lock"
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("reviews.daily.readonlyNote")
      } else {
        LorvexEmptyStatePanel(
          title: String(localized: "reviews.daily.readonly_empty.title", defaultValue: "No review", table: "Localizable", bundle: LorvexL10n.bundle),
          message: String(localized: "reviews.daily.readonly_empty", defaultValue: "No review was written on this day.", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "square.and.pencil",
          tint: .secondary,
          style: .inline
        )
        .accessibilityIdentifier("reviews.daily.readonlyEmpty")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func isEmptyReview(_ review: DailyReviewEntry) -> Bool {
    review.summary.isEmpty && review.mood == nil && review.energyLevel == nil
      && (review.wins ?? "").isEmpty && (review.blockers ?? "").isEmpty
      && (review.learnings ?? "").isEmpty
  }

  /// A saved rating on the same dot scale the editable review uses, disabled,
  /// so a rating reads the same in and past the write window.
  private func scale(
    _ label: String, value: Int?, low: String, high: String, dotLabel: @escaping (Int) -> String,
    identifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      LorvexPageLabel(label)
      LorvexDotScale(
        value: .constant(value), lowLabel: low, highLabel: high, dotLabel: dotLabel,
        identifierPrefix: identifier, isEnabled: false)
    }
    .frame(maxWidth: .infinity)
  }

  /// A written field under its name; nothing when the field was left empty.
  @ViewBuilder
  private func written(_ label: String, _ text: String?) -> some View {
    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        LorvexPageLabel(label)
        Text(text)
          .font(LorvexDesign.Typography.primaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
    }
  }
}
