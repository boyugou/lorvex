import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

/// The `systemSmall` Today widget: the lead task alone — its circle (the Done
/// control, a filling ring while its time runs), the widget's title, the task's
/// title and line — and one quiet line saying how many tasks follow. With tasks
/// left but no lead, it says what is left of the day and names the top two.
/// Tapping anywhere else opens Today through the entry view's `widgetURL`.
struct SmallSystemWidgetView: View {
  let model: WidgetRenderModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.state == .fallback {
        // A broken/missing snapshot is honestly "unavailable", never the
        // reassuring "All clear": counts of 0 here mean "couldn't load", not
        // "everything done". Mirrors the medium/large fallback treatment.
        unavailable
      } else if let lead = model.lead {
        content(lead)
      } else if model.remainingCount > 0 {
        dayContent
      } else {
        allClear
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // No opaque fill here: the entry view's `.containerBackground` already
    // supplies the widget's backing material.
  }

  private func content(_ lead: WidgetLeadRender) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        WidgetLeadRing(lead: lead, diameter: 40)
        Text(model.headline)
          .font(.caption.weight(.semibold))
          .foregroundStyle(LorvexDesign.Palette.accent)
        Spacer(minLength: 0)
      }
      Text(lead.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.primary)
        .lineLimit(2)
        // The title is the user's private content on a Home Screen / StandBy
        // surface; redact it when the device locks.
        .privacySensitive()
      if let line = lead.line {
        WidgetLeadLine(line: line, isOverdue: lead.isOverdue)
      }
      Spacer(minLength: 0)
      WidgetFootLine(model: model)
    }
  }

  /// Tasks left, none leading: the title, how many are left and the work
  /// they hold, then the top titles. The rows drop their metadata column; the
  /// small tile is too narrow for two columns.
  private var dayContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.headline)
        .font(.caption.weight(.semibold))
        .foregroundStyle(LorvexDesign.Palette.accent)
      if let dayLeft = model.dayLeft {
        Text(dayLeft)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      if let dayWork = model.dayWork {
        Text(dayWork)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      VStack(alignment: .leading, spacing: 2) {
        ForEach(model.taskRows) { row in
          Text(row.title)
            .font(.caption)
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .privacySensitive()
        }
      }
      .padding(.top, 4)
      Spacer(minLength: 0)
      WidgetFootLine(model: model)
    }
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
  /// already-localized "unavailable" copy, visually distinct from the
  /// celebratory green `allClear` so a broken snapshot never reads as
  /// "everything done".
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
}
