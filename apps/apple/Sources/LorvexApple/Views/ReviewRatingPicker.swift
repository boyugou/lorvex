import SwiftUI

/// A compact 1…N rating control: a row of tappable symbols that fill up to the
/// selected value. Replaces a bare number stepper for the daily review's mood
/// and energy so the page reads as a deliberate reflection surface rather than a
/// form field. The value is optional: `nil` shows an empty row (the human hasn't
/// rated it), and tapping the current value clears it back to `nil`, so an
/// untouched review never records a fabricated score. Stays fully accessible —
/// VoiceOver sees one adjustable element.
struct ReviewRatingPicker: View {
  let title: String
  let symbol: String
  let filledSymbol: String
  let tint: Color
  @Binding var value: Int?
  var range: ClosedRange<Int> = 1...5

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 8) {
        ForEach(Array(range), id: \.self) { level in
          Button {
            // Tapping the current value clears it (a genuine "unset"); any other
            // tap selects that level.
            lorvexAnimated(.snappy(duration: 0.18)) {
              value = (value == level) ? nil : level
            }
          } label: {
            Image(systemName: level <= (value ?? 0) ? filledSymbol : symbol)
              .imageScale(.large)
              .foregroundStyle(level <= (value ?? 0) ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .accessibilityElement()
    .accessibilityLabel(title)
    .accessibilityValue(
      value.map {
        String(
          format: String(
            localized: "reviews.daily.rating_accessibility", defaultValue: "%lld out of 5", table: "Localizable", bundle: LorvexL10n.bundle),
          $0)
      } ?? String(localized: "reviews.daily.rating_unset", defaultValue: "Not rated", table: "Localizable", bundle: LorvexL10n.bundle)
    )
    .accessibilityAdjustableAction { direction in
      lorvexAnimated(.snappy(duration: 0.18)) {
        switch direction {
        case .increment: value = min(range.upperBound, (value ?? range.lowerBound - 1) + 1)
        case .decrement:
          // Stepping below the lowest rating returns to the unset state.
          if let current = value {
            value = current > range.lowerBound ? current - 1 : nil
          }
        @unknown default: break
        }
      }
    }
  }
}
