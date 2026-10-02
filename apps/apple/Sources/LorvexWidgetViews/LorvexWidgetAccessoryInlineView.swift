import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

/// The `accessoryInline` Lock Screen family: one line with a leading SF Symbol
/// in the system's tinted slot — a few words about the lead task, then its
/// title ("Until 3:00 PM · Review the spec"), the fact first the way the
/// Calendar inline leads with its time, so a long title truncates before the
/// fact does. It renders as one text unit, so its content redacts together on
/// a locked device.
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
    } else if model.lead == nil, model.remainingCount > 0, !model.dayLineChoices.isEmpty {
      // Tasks left, none leading: how much is left, worded as long as the
      // line allows. It names no task, so it stays legible on a locked Lock
      // Screen.
      LorvexFirstFittingLine(model.dayLineChoices) {
        Label($0, systemImage: "list.bullet")
          .lineLimit(1)
      }
    } else if model.lead == nil {
      // Nothing left today: a non-sensitive glance that stays legible on a
      // locked Lock Screen (nothing to redact). "All clear" mirrors the small
      // family's empty treatment so the two surfaces speak the same way.
      Label(
        String(
          localized: "widget.small.all_clear",
          defaultValue: "All clear",
          table: "Localizable",
          bundle: WidgetL10n.bundle),
        systemImage: "checkmark.seal")
        .lineLimit(1)
    } else if let lead = model.lead {
      // The title is the user's private content, so the line is sensitive and
      // redacts when the device locks.
      Label(
        [lead.shortLine, lead.title].compactMap { $0 }.joined(separator: " · "),
        systemImage: lead.isOverdue ? "exclamationmark.circle" : "circle"
      )
      .lineLimit(1)
      .privacySensitive()
    }
  }
}
