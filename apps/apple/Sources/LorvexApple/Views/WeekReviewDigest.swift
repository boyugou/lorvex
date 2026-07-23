import AppKit
import LorvexCore
import SwiftUI

/// The Week scope's reflection column: a read-only digest of the daily reviews
/// written in the viewed week. Each row names the day, shows the summary, and
/// surfaces mood / energy glyphs; tapping a row jumps to that day in Day scope.
/// The week is summary-only — there is no writing surface here.
struct WeekReviewDigest: View {
  let reviews: [DailyReviewEntry]
  /// Open that day in Day scope.
  var onSelectDay: (String) -> Void = { _ in }

  var body: some View {
    // Newest-first for the digest row list.
    let sortedReviews = reviews.sorted { $0.date > $1.date }
    return ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        Text(LocalizedStringResource("reviews.weekly.digest_title", defaultValue: "This week’s reviews", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.sectionHeader)

        if sortedReviews.isEmpty {
          LorvexEmptyStatePanel(
            title: String(localized: "reviews.weekly.digest_empty.title", defaultValue: "No reviews yet", table: "Localizable", bundle: LorvexL10n.bundle),
            message: String(localized: "reviews.weekly.digest_empty", defaultValue: "No daily reviews written this week.", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "text.badge.checkmark",
            tint: .secondary,
            style: .inline
          )
        } else {
          ForEach(sortedReviews, id: \.date) { review in
            Button {
              onSelectDay(review.date)
            } label: {
              WeekReviewDigestRow(review: review)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reviews.weekly.digest.row.\(review.date)")
          }
        }
      }
      .padding(LorvexDesign.Spacing.l)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityIdentifier("reviews.weekly.digest")
  }
}

private struct WeekReviewDigestRow: View {
  let review: DailyReviewEntry
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Text(formattedDate)
          .font(LorvexDesign.Typography.primaryEmphasis)

        Spacer(minLength: LorvexDesign.Spacing.s)

        if let mood = review.mood {
          scoreBadge(systemImage: "heart.fill", tint: .pink, value: mood)
        }
        if let energy = review.energyLevel {
          scoreBadge(systemImage: "bolt.fill", tint: .orange, value: energy)
        }
      }

      if !review.summary.isEmpty {
        Text(review.summary)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .lorvexCard()
    // Hover lift + accent ring so the tappable rows read as interactive, with a
    // pointing-hand cursor on hover — mirroring the app's other clickable cards.
    .overlay {
      if hovering {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous)
          .strokeBorder(LorvexDesign.Palette.accent.opacity(0.35), lineWidth: 1)
      }
    }
    .scaleEffect(hovering ? 1.006 : 1)
    .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 6, y: 2)
    .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
    .onHover { inside in
      lorvexAnimated(.easeOut(duration: 0.14)) { hovering = inside }
      if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
    .accessibilityElement(children: .combine)
  }

  private var formattedDate: String {
    if let date = LorvexDateFormatters.ymd.date(from: review.date) {
      return date.formatted(.dateTime.weekday(.wide).month().day())
    }
    return review.date
  }

  private func scoreBadge(systemImage: String, tint: Color, value: Int) -> some View {
    Label("\(value)", systemImage: systemImage)
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .foregroundStyle(tint)
      .labelStyle(.titleAndIcon)
      .monospacedDigit()
  }
}
