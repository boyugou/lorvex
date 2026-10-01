import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

enum SystemWidgetLayout {
  case medium
  case large

  var ringDiameter: CGFloat {
    switch self {
    case .medium: 40
    case .large: 56
    }
  }

  var titleFont: Font {
    switch self {
    case .medium: .subheadline.weight(.semibold)
    case .large: .title3.weight(.semibold)
    }
  }

  var titleLines: Int {
    switch self {
    case .medium: 1
    case .large: 2
    }
  }
}

/// The `systemMedium` and `systemLarge` Today widgets: the lead task with its
/// circle, then the tasks after it in Today's order, each with its own circle
/// to complete it. With tasks left but no lead, a line saying what is left of
/// the day takes the lead's place and the list starts at its top. Large opens with the title and the assistant's briefing in
/// its serif voice, and closes with how much got done today. The briefing gets
/// two lines, or three when every row still fits under it. The rows are as
/// many as the height holds: at a larger text size the last rows give way (the
/// foot line's "N more today" counts them) instead of the foot line being
/// clipped.
struct SystemWidgetView: View {
  let model: WidgetRenderModel
  let layout: SystemWidgetLayout

  var body: some View {
    let metrics = LorvexWidgetViewMetrics.metrics(for: model.family)
    VStack(alignment: .leading, spacing: 6) {
      if model.state == .fallback {
        unavailable
      } else if model.lead != nil || model.remainingCount > 0 {
        let lead = model.lead
        let fittingRowCounts = Array(stride(from: model.taskRows.count, through: 0, by: -1))
        if metrics.showsBriefing, let briefing = model.briefing {
          // The briefing takes a third line only when every row still fits
          // under it; otherwise it keeps two lines and the rows keep their room.
          ViewThatFits(in: .vertical) {
            leadContent(
              lead, briefing: briefing, briefingLines: 3, rowCounts: [model.taskRows.count])
            leadContent(lead, briefing: briefing, briefingLines: 2, rowCounts: fittingRowCounts)
          }
        } else {
          leadContent(lead, briefing: nil, briefingLines: 0, rowCounts: fittingRowCounts)
        }
      } else {
        allClear
      }
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
    // No opaque fill here: the entry view's `.containerBackground` already
    // supplies the widget's backing material.
  }

  /// The lead task's page: on large the title and the briefing, when there is
  /// one, in at most `briefingLines` lines; then the lead block and, under it,
  /// the first of `rowCounts` whose rows and foot line fit.
  private func leadContent(
    _ lead: WidgetLeadRender?, briefing: String?, briefingLines: Int, rowCounts: [Int]
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if layout == .large {
        Text(model.headline)
          .font(.caption.weight(.semibold))
          .foregroundStyle(LorvexDesign.Palette.accent)
        if let briefing {
          // The assistant's note on the day is the user's private content;
          // redact it when the device locks.
          Text(briefing, serifVoice: .assistantSecondary)
            .foregroundStyle(.secondary)
            .lineLimit(briefingLines)
            .privacySensitive()
        }
      }
      if let lead {
        WidgetLeadBlock(
          lead: lead, label: layout == .large ? nil : model.headline,
          ringDiameter: layout.ringDiameter, titleFont: layout.titleFont,
          titleLines: layout.titleLines)
      } else {
        dayHeader
      }
      ViewThatFits(in: .vertical) {
        ForEach(rowCounts, id: \.self) { count in
          nextRowsAndFoot(showing: count)
        }
      }
    }
  }

  /// The first `count` rows and the foot line under them. Gaps are
  /// explicit paddings rather than stack spacing, so the zero-height spacer
  /// adds none: `ViewThatFits` measures this at its natural height, and on
  /// medium two rows fit with only a few points to spare. The rows need no
  /// gap between them; each is as tall as its 32pt complete button.
  private func nextRowsAndFoot(showing count: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if count > 0 {
        ForEach(model.taskRows.prefix(count)) { row in
          WidgetTaskRowView(row: row, interactive: true)
        }
      }
      Spacer(minLength: 0)
      WidgetFootLine(model: model, showsDone: layout == .large, shownRowCount: count)
        .padding(.top, 4)
    }
  }

  /// The lead's place when no task leads: on medium the title, then what is
  /// left of the day.
  private var dayHeader: some View {
    VStack(alignment: .leading, spacing: 2) {
      if layout == .medium {
        Text(model.headline)
          .font(.caption.weight(.semibold))
          .foregroundStyle(LorvexDesign.Palette.accent)
      }
      if let dayLine = model.dayLine {
        Text(dayLine)
          .font(layout.titleFont)
          .foregroundStyle(Color.primary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var allClear: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "checkmark.seal.fill")
          .foregroundStyle(LorvexDesign.Palette.done)
          .accessibilityHidden(true)
        Text("widget.small.all_clear", bundle: WidgetL10n.bundle)
          .font(.headline)
          .foregroundStyle(Color.primary)
      }
      Text(model.subheadline)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
      WidgetFootLine(model: model, showsDone: true)
    }
  }

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
      Spacer(minLength: 0)
      Text(model.statusText)
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
  }
}
