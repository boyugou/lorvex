import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// The `accessoryCircular` Lock Screen family for the Today widget: while the
/// lead task's time runs, its ring fills and holds the minutes left; otherwise
/// the empty ring holds how many tasks are left today. A day with nothing left
/// shows a checkmark; a failed snapshot shows an unavailable glyph.
struct AccessoryCircularWidgetView: View {
  let model: WidgetRenderModel

  var body: some View {
    switch model.circularContent {
    case .unavailable:
      // Broken/missing snapshot: an attention glyph (not the checkmark, which
      // reads "all clear") with the builder's localized "unavailable" status as
      // the accessibility label. `widgetAccentable` keeps it legible when tinted.
      Image(systemName: "exclamationmark.circle")
        .widgetAccentable()
        .accessibilityLabel(model.statusText.isEmpty ? model.subheadline : model.statusText)
    case .empty:
      // Nothing left today: a checkmark, rather than an empty ring that a
      // glance could mistake for "0% done".
      Image(systemName: "checkmark")
        .widgetAccentable()
        .accessibilityLabel(
          String(
            localized: "widget.small.all_clear",
            defaultValue: "All clear",
            table: "Localizable",
            bundle: WidgetL10n.bundle))
    case .running(let minutesLeft):
      ring {
        VStack(spacing: -2) {
          Text("\(minutesLeft)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .monospacedDigit()
          Text("widget.circular.min", bundle: WidgetL10n.bundle)
            .font(.caption2)
        }
      }
      .accessibilityLabel(
        String(
          localized: "widget.circular.running.a11y",
          defaultValue: "\(LorvexDurationFormat.minutes(minutesLeft, style: .spoken)) left",
          table: "Localizable", bundle: WidgetL10n.bundle))
    case .remaining(let remaining):
      ring {
        VStack(spacing: -2) {
          Text("\(remaining)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .monospacedDigit()
          Text("widget.circular.left", bundle: WidgetL10n.bundle)
            .font(.caption2)
        }
      }
      .accessibilityLabel(
        String(
          localized: "widget.circular.a11y",
          defaultValue: "\(remaining) tasks left today",
          table: "Localizable", bundle: WidgetL10n.bundle))
    }
  }

  /// The ring drawn in the Lock Screen's vibrant material: a faint track and
  /// an accentable arc that starts at the top, like the app's task ring.
  private func ring(@ViewBuilder _ center: () -> some View) -> some View {
    ZStack {
      Circle()
        .stroke(.tertiary, lineWidth: 3)
      LorvexProgressArc(fraction: model.lead?.progress ?? 0, style: .primary, lineWidth: 3)
        .widgetAccentable()
      center()
        .widgetAccentable()
    }
    .padding(2)
  }
}
