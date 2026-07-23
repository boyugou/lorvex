import LorvexWidgetKitSupport
import SwiftUI

/// The `accessoryInline` Lock Screen family: a single short line with an optional
/// leading SF Symbol in the system's tinted slot. It renders as one text unit, so
/// its content redacts together on a locked device — there is no way to show a
/// count next to a private title while redacting only the title.
struct AccessoryInlineWidgetView: View {
  let model: WidgetRenderModel

  var body: some View {
    if model.state == .fallback {
      // A broken/missing snapshot is "unavailable", not "All clear": the builder's
      // already-localized status text ("Open Lorvex to refresh" / "Snapshot
      // unavailable") is non-sensitive and stays legible when locked. Never show
      // the reassuring checkmark for a snapshot that failed to load.
      Label(
        model.statusText.isEmpty ? model.subheadline : model.statusText,
        systemImage: "exclamationmark.circle"
      )
      .lineLimit(1)
    } else if model.focusCount == 0 {
      // No focus tasks: a non-sensitive glance that stays legible on a locked
      // Lock Screen (nothing to redact). "All clear" mirrors the small family's
      // empty treatment so the two Focus surfaces speak the same way.
      Label(
        String(
          localized: "widget.small.all_clear",
          defaultValue: "All clear",
          table: "Localizable",
          bundle: WidgetL10n.bundle),
        systemImage: "checkmark.seal")
        .lineLimit(1)
    } else {
      // The headline is the top focus task's title — the user's private content —
      // so mark the line sensitive to redact it when the device locks. Only the
      // title is shown (not the count): inline's one-line budget is tight, and the
      // count is already carried by the rectangular and circular families.
      Label(model.headline, systemImage: "scope")
        .lineLimit(1)
        .privacySensitive()
    }
  }
}
