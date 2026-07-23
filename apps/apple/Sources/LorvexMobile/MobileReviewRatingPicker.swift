import SwiftUI

struct MobileReviewRatingPicker: View {
  let title: String
  let symbol: String
  let filledSymbol: String
  let tint: Color
  let identifierPrefix: String
  @Binding var value: Int?
  var isEnabled = true
  var canClear = true
  var range: ClosedRange<Int> = 1...5

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 4) {
        ForEach(Array(range), id: \.self) { level in
          ratingButton(level)
        }
        // Only surface Clear once there's a value to clear, so an unrated control
        // shows just its glyphs instead of a trailing ✕ that reads like a 6th option.
        if isEnabled, canClear, value != nil {
          clearButton
        }
      }
    }
    // One selection tick per rating change; the per-glyph bounce lives on the
    // tapped glyph itself (see MobileReviewRatingGlyph).
    .lorvexSensoryFeedback(.selection, trigger: value)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(accessibilityValue)
    .accessibilityAdjustableAction(adjustRating)
    .accessibilityIdentifier(identifierPrefix)
  }

  private func ratingButton(_ level: Int) -> some View {
    MobileReviewRatingGlyph(
      symbol: level <= (value ?? 0) ? filledSymbol : symbol,
      isFilled: level <= (value ?? 0),
      tint: tint,
      isSelected: value == level,
      accessibilityLabel: String(
        format: String(
          localized: "review.rating.level.a11y", defaultValue: "%@ %lld out of 5",
          table: "Localizable", bundle: MobileL10n.bundle),
        title,
        level
      ),
      accessibilityIdentifier: "\(identifierPrefix).level\(level)"
    ) {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
        value = level
      }
    }
    .disabled(!isEnabled)
  }

  private var clearButton: some View {
    Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
        value = nil
      }
    } label: {
      Image(systemName: "xmark.circle.fill")
        .imageScale(.medium)
        .foregroundStyle(.tertiary)
        .frame(width: 36, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled || !canClear || value == nil)
    .accessibilityLabel(
      String(
        format: String(
          localized: "review.rating.clear.a11y", defaultValue: "Clear %@ rating",
          table: "Localizable", bundle: MobileL10n.bundle),
        title
      )
    )
    .accessibilityIdentifier("\(identifierPrefix).clear")
  }

  private var accessibilityValue: String {
    if let value {
      return String(
        format: String(
          localized: "review.rating.value.a11y", defaultValue: "%lld out of 5",
          table: "Localizable", bundle: MobileL10n.bundle),
        value
      )
    }
    return String(
      localized: "review.rating.unset.a11y", defaultValue: "Not rated", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  private func adjustRating(_ direction: AccessibilityAdjustmentDirection) {
    guard isEnabled else { return }
    switch direction {
    case .increment:
      value = min(range.upperBound, (value ?? range.lowerBound - 1) + 1)
    case .decrement:
      guard let current = value else { return }
      value = current > range.lowerBound ? current - 1 : nil
    @unknown default:
      break
    }
  }
}

/// A single tappable rating glyph. Owns a per-glyph pulse so `symbolEffect(.bounce)`
/// fires only on the glyph the user just tapped, rather than every filled glyph in
/// the row. Unselected glyphs use a faint version of the control's own tint (not a
/// neutral gray) so the row reads as "tap to rate" and keeps its identity.
private struct MobileReviewRatingGlyph: View {
  let symbol: String
  let isFilled: Bool
  let tint: Color
  let isSelected: Bool
  let accessibilityLabel: String
  let accessibilityIdentifier: String
  let select: () -> Void
  @State private var pulse = 0

  var body: some View {
    Button {
      pulse += 1
      select()
    } label: {
      Image(systemName: symbol)
        .imageScale(.large)
        .foregroundStyle(isFilled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.28)))
        .symbolEffect(.bounce, value: pulse)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}
