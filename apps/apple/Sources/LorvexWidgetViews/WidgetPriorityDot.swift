import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

/// Priority-dot tint from the canonical `priorityTint` ramp (P1 red, P2 orange,
/// P3 quiet) for a raw priority `tier`, or nil when the tier is absent or is not
/// a valid priority. Every widget task surface resolves the dot color through
/// this one function so the ramp can never diverge between families.
func lorvexWidgetPriorityDotTint(tier: Int?) -> Color? {
  guard let tier, let priority = LorvexTask.Priority(tier: tier) else { return nil }
  return priority.priorityTint
}

/// The priority dot shown on widget task rows: a fixed 7pt circle in the
/// canonical priority tint, hidden from VoiceOver because the enclosing row's
/// accessibility label already voices the priority. `color` nil renders
/// `fallback`. One definition so the diameter never drifts between families.
struct WidgetPriorityDot: View {
  let color: Color?
  var fallback: Color = .clear
  var topPadding: Double = 4

  static let diameter: Double = 7

  var body: some View {
    Circle()
      .fill(color ?? fallback)
      .frame(width: Self.diameter, height: Self.diameter)
      .padding(.top, topPadding)
      .accessibilityHidden(true)
  }
}
