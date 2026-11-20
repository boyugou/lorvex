import LorvexCore
import SwiftUI

/// A past entry shows only the writing and ratings recorded on that day.
struct DailyReviewReadOnlyView: View {
  let review: DailyReviewEntry?

  private typealias Copy = ReviewCalmCopy

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
      if let review, !isEmptyReview(review) {
        written(Copy.noteLabel, review.summary)
        written(Copy.winsLabel, review.wins)
        written(Copy.blockersLabel, review.blockers)
        written(Copy.learningsLabel, review.learnings)

        if let mood = review.mood {
          rating(Copy.feelLabel, word: Copy.feelWord(mood), value: Copy.feelDot(mood), id: "reviews.readonly.mood")
        }
        if let energy = review.energyLevel {
          rating(Copy.energyLabel, word: Copy.energyWord(energy), value: Copy.energyDot(energy), id: "reviews.readonly.energy")
        }
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

  private func rating(_ label: String, word: String, value: String, id: String) -> some View {
    LabeledContent(label, value: word)
      .font(LorvexDesign.Typography.primaryText)
      .accessibilityValue("\(word), \(value)")
      .accessibilityIdentifier(id)
  }

  /// A written field under its name; nothing when the field was left empty.
  @ViewBuilder
  private func written(_ label: String, _ text: String?) -> some View {
    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        LorvexPageLabel(label)
        Text(userContent: text)
          .font(LorvexDesign.Typography.primaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
    }
  }
}
