import LorvexCore
import SwiftUI

/// A past entry shows only the writing and ratings recorded on that day.
struct DailyReviewReadOnlyView: View {
  let review: DailyReviewEntry?

  private typealias Copy = ReviewCalmCopy

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
      if let review, review.hasJournalContent {
        LorvexJournalEntryBody(review: review, feeling: Copy.feelWord, energy: Copy.energyWord)
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
}
