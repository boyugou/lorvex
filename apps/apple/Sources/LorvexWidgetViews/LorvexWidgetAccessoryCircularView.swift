import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// The `accessoryCircular` Lock Screen family for the Focus widget. It shows the
/// remaining focus count without inventing a completion ratio from unrelated
/// global completed-task statistics. A genuinely empty plan shows the Focus
/// glyph; a failed snapshot shows an unavailable glyph.
struct AccessoryCircularWidgetView: View {
  let model: WidgetRenderModel

  /// Whether the circular renders the unavailable glyph, a remaining count, or
  /// the empty-state glyph. Split out as a pure classifier so the boundaries are
  /// unit-testable without rendering the view.
  enum Content: Equatable {
    case unavailable
    case empty
    case remaining(Int)
  }

  nonisolated static func content(
    state: WidgetRenderState = .content, focusCount: Int
  ) -> Content {
    if state == .fallback { return .unavailable }
    let remaining = max(0, focusCount)
    return remaining == 0 ? .empty : .remaining(remaining)
  }

  var body: some View {
    switch Self.content(state: model.state, focusCount: model.focusCount) {
    case .unavailable:
      // Broken/missing snapshot: an attention glyph (not the Focus `scope`, which
      // reads "no focus set") with the builder's localized "unavailable" status as
      // the accessibility label. `widgetAccentable` keeps it legible when tinted.
      Image(systemName: "exclamationmark.circle")
        .widgetAccentable()
        .accessibilityLabel(model.statusText.isEmpty ? model.subheadline : model.statusText)
    case .empty:
      // No focus tasks and nothing completed today: the Focus glyph reads as "no
      // focus set" rather than an empty ring that a glance could mistake for
      // "0% done". `widgetAccentable` keeps it legible in the tinted render mode.
      Image(systemName: "scope")
        .widgetAccentable()
        .accessibilityLabel(
          String(
            localized: "widget.small.all_clear",
            defaultValue: "All clear",
            table: "Localizable",
            bundle: WidgetL10n.bundle))
    case .remaining(let remaining):
      Text("\(remaining)")
        .font(.system(.title2, design: .rounded).weight(.bold))
        .widgetAccentable()
        .accessibilityLabel(
          String(
            localized: "widget.circular.a11y",
            defaultValue: "\(remaining) focus tasks remaining",
            table: "Localizable", bundle: WidgetL10n.bundle))
    }
  }
}
