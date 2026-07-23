import LorvexCore
import SwiftUI

/// The Day-scope reflection for a past day outside the interactive write
/// window: the saved review rendered statically (no editors, no save footer),
/// or an empty-state note when no review was written that day. The date strip
/// names the day; this view only shows what was recorded.
struct DailyReviewReadOnlyView: View {
  let review: DailyReviewEntry?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      if let review, !isEmptyReview(review) {
        readOnlyField(
          title: String(localized: "reviews.daily.title", defaultValue: "Daily Review", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "square.and.pencil",
          tint: .blue,
          body: review.summary
        )

        HStack(spacing: LorvexDesign.Spacing.l) {
          readOnlyRating(
            title: String(localized: "reviews.daily.mood", defaultValue: "Mood", table: "Localizable", bundle: LorvexL10n.bundle),
            filledSymbol: "heart.fill",
            emptySymbol: "heart",
            tint: .pink,
            value: review.mood
          )
          readOnlyRating(
            title: String(localized: "reviews.daily.energy", defaultValue: "Energy", table: "Localizable", bundle: LorvexL10n.bundle),
            filledSymbol: "bolt.fill",
            emptySymbol: "bolt",
            tint: .orange,
            value: review.energyLevel
          )
        }

        if let wins = review.wins, !wins.isEmpty {
          readOnlyField(
            title: String(localized: "reviews.daily.wins", defaultValue: "Wins", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "trophy.fill", tint: .yellow, body: wins)
        }
        if let blockers = review.blockers, !blockers.isEmpty {
          readOnlyField(
            title: String(localized: "reviews.daily.blockers", defaultValue: "Blockers", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "exclamationmark.triangle.fill", tint: .red, body: blockers)
        }
        if let learnings = review.learnings, !learnings.isEmpty {
          readOnlyField(
            title: String(localized: "reviews.daily.learnings", defaultValue: "Learnings", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "lightbulb.fill", tint: .teal, body: learnings)
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
    .padding(LorvexDesign.Spacing.l)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func isEmptyReview(_ review: DailyReviewEntry) -> Bool {
    review.summary.isEmpty && review.mood == nil && review.energyLevel == nil
      && (review.wins ?? "").isEmpty && (review.blockers ?? "").isEmpty
      && (review.learnings ?? "").isEmpty
  }

  /// A static, accent-railed read-only section mirroring the editable prompt
  /// panel's look without any editor.
  private func readOnlyField(title: String, systemImage: String, tint: Color, body: String)
    -> some View
  {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      Capsule().fill(tint.opacity(0.7)).frame(width: 3)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        Label(title, systemImage: systemImage)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(tint)
        Text(body)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.06), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.m)
        .stroke(.separator.opacity(0.10), lineWidth: 0.5)
    }
  }

  /// A static row of filled / hollow rating glyphs for a saved mood / energy
  /// score; renders "—" when the human left it unrated. Uses the same
  /// filled/outline glyph pair as the editable ``ReviewRatingPicker`` so a saved
  /// rating reads identically whether the day is in or past the write window.
  private func readOnlyRating(
    title: String, filledSymbol: String, emptySymbol: String, tint: Color, value: Int?
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      if let value {
        HStack(spacing: 4) {
          ForEach(1...5, id: \.self) { level in
            Image(systemName: level <= value ? filledSymbol : emptySymbol)
              .foregroundStyle(level <= value ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
          }
        }
      } else {
        Text(verbatim: "—").foregroundStyle(.tertiary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
  }
}
