import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

/// Purpose-built `systemSmall` layout. The shared system layout (header + two
/// rows + footer) truncated titles ("Reply to the inve…") and crammed the footer
/// at 158×158, so small instead leads with a glanceable focus count and the
/// single next task — what you actually want from a corner of the Home Screen.
struct SmallSystemWidgetView: View {
  let model: WidgetRenderModel

  var body: some View {
    link {
      VStack(alignment: .leading, spacing: 0) {
        header
        Spacer(minLength: 8)
        if model.state == .fallback {
          // A broken/missing snapshot is honestly "unavailable", never the
          // reassuring green "All clear": counts of 0 here mean "couldn't load",
          // not "everything done". Mirrors the medium/large fallback treatment.
          unavailable
        } else if model.state == .empty || model.taskRows.isEmpty {
          allClear
        } else {
          content
        }
        Spacer(minLength: 0)
      }
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // No opaque fill here: the entry view's `.containerBackground` already
      // supplies the widget's backing material.
    }
  }

  private var header: some View {
    HStack(spacing: 5) {
      Image(systemName: "scope")
        .foregroundStyle(LorvexDesign.Palette.focus)
        .accessibilityHidden(true)
      Text(model.headline)
        .foregroundStyle(Color.primary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .font(.subheadline.weight(.semibold))
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(model.focusCountText)
          .font(.system(size: 38, weight: .bold, design: .rounded))
          .foregroundStyle(Color.primary)
        Text("widget.small.in_focus", bundle: WidgetL10n.bundle)
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }
      if let attention = model.attentionCountText {
        Text(attention)
          .font(.caption2.weight(.medium))
          .foregroundStyle(LorvexDesign.Palette.dueSoon)
          .lineLimit(1)
      }
      if let next = model.taskRows.first {
        nextTask(next)
      }
    }
  }

  private func nextTask(_ row: WidgetTaskRenderRow) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .top, spacing: 6) {
        WidgetPriorityDot(color: row.priorityTintColor)
        Text(row.title)
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.primary)
          .lineLimit(2)
          // The next task's title is the user's private content on a Home
          // Screen / StandBy surface; redact it when the device locks.
          .privacySensitive()
      }
      if remainingCount > 0 {
        Text(String(
          localized: "widget.small.more",
          defaultValue: "+\(remainingCount) more",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
          .font(.caption2)
          .foregroundStyle(Color.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      [
        String(
          localized: "widget.small.next",
          defaultValue: "Next",
          table: "Localizable",
          bundle: WidgetL10n.bundle),
        row.priorityLabel,
        row.title,
      ]
        .compactMap { $0 }.joined(separator: ", "))
  }

  private var allClear: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "checkmark.seal.fill")
        .font(.title)
        .foregroundStyle(LorvexDesign.Palette.done)
      Text("widget.small.all_clear", bundle: WidgetL10n.bundle)
        .font(.headline)
        .foregroundStyle(Color.primary)
      Text("widget.small.all_clear.subtitle", bundle: WidgetL10n.bundle)
        .font(.caption)
        .foregroundStyle(Color.secondary)
    }
  }

  /// Honest treatment for `state == .fallback` (missing file / corrupt JSON /
  /// mis-provisioned App Group): a muted attention glyph and the builder's
  /// already-localized "unavailable" copy, visually distinct from the celebratory
  /// green `allClear` so a broken snapshot never reads as "everything done".
  private var unavailable: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "exclamationmark.circle")
        .font(.title2)
        .foregroundStyle(Color.secondary)
      Text(model.subheadline)
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// Focus tasks beyond the one shown as "next".
  private var remainingCount: Int {
    max(0, model.focusCount - 1)
  }

  @ViewBuilder
  private func link(@ViewBuilder _ content: () -> some View) -> some View {
    if let urlString = model.urlString, let url = URL(string: urlString) {
      Link(destination: url) { content() }
    } else {
      content()
    }
  }
}
