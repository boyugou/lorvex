import LorvexCore
import SwiftUI

/// Apple-Calendar-style rounded segmented control: a soft capsule track with the
/// selected option as a raised, filled pill. Replaces the stock boxy
/// `.pickerStyle(.segmented)` for the app's two-to-four-way toggles so they share
/// one rounded aesthetic.
///
/// Generic over any `Hashable` value; the caller supplies the option list and a
/// label for each. Keep it to a handful of short options — for long lists the
/// stock `Picker` menu still reads better.
struct LorvexSegmentedControl<Value: Hashable>: View {
  let options: [Value]
  @Binding var selection: Value
  let title: (Value) -> String
  var accessibilityIdentifier: String? = nil
  var accessibilityLabel: String? = nil
  /// Optional per-option leading color dot (e.g. a priority tint), so options
  /// read by color at a glance. Nil → no dot (the default for plain toggles).
  var optionTint: ((Value) -> Color?)? = nil

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, value in
        segment(value)
      }
    }
    .padding(2)
    .background(Capsule().fill(Color.secondary.opacity(0.14)))
    .accessibilityElement(children: .contain)
    .modifier(OptionalA11y(label: accessibilityLabel, identifier: accessibilityIdentifier))
  }

  private func segment(_ value: Value) -> some View {
    let isSelected = selection == value
    return Button {
      lorvexAnimated(.snappy(duration: 0.16)) { selection = value }
    } label: {
      HStack(spacing: 5) {
        if let tint = optionTint?(value) {
          Circle().fill(tint).frame(width: 6, height: 6)
        }
        Text(title(value))
          .font(LorvexDesign.Typography.secondaryText.weight(.medium))
          .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      }
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .padding(.vertical, 5)
        .frame(minWidth: 44)
        .background {
          if isSelected {
            Capsule()
              .fill(Color(nsColor: .controlColor))
              .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
          }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}

private struct OptionalA11y: ViewModifier {
  let label: String?
  let identifier: String?

  func body(content: Content) -> some View {
    content
      .accessibilityLabel(label ?? "")
      .accessibilityIdentifier(identifier ?? "")
  }
}
