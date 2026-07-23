import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

enum SystemWidgetLayout {
  case small
  case medium
  case large

  var titleFont: Font {
    switch self {
    case .small: .headline
    case .medium, .large: .title3.weight(.semibold)
    }
  }

  var rowLimit: Int {
    switch self {
    case .small: WidgetFamilyKind.systemSmall.maxTaskRows
    case .medium: WidgetFamilyKind.systemMedium.maxTaskRows
    case .large: WidgetFamilyKind.systemLarge.maxTaskRows
    }
  }

  /// Whether task rows should render an interactive Complete button.
  /// Only medium and large widgets have enough horizontal space.
  var isInteractive: Bool {
    switch self {
    case .small: false
    case .medium, .large: true
    }
  }

  /// Whether interactive rows should show only the two primary actions
  /// (complete + defer) rather than the full five. Medium is too narrow for
  /// five ≥44pt targets alongside the title; large has the room.
  var compactActions: Bool {
    switch self {
    case .small, .medium: true
    case .large: false
    }
  }
}

struct SystemWidgetView: View {
  let model: WidgetRenderModel
  let layout: SystemWidgetLayout

  var body: some View {
    let metrics = LorvexWidgetViewMetrics.metrics(for: model.family)
    VStack(alignment: .leading, spacing: 8) {
      header
      if metrics.showsBriefing {
        // `subheadline` renders the user's saved briefing text when one exists
        // (falling back to a static string only in the empty/stale states);
        // redact it when the device locks.
        Text(model.subheadline)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .privacySensitive()
      }
      taskContent
      Spacer(minLength: 0)
      footer
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
    // No opaque fill here: the entry view's `.containerBackground` already
    // supplies the widget's backing material.
  }

  private var header: some View {
    // A focus-tinted glyph carries the brand accent; the old "Live/Ready/Saved"
    // status badge read as debug chrome and is gone — staleness now shows only as
    // the subtle footer capsule once content is actually old.
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "scope")
        .font(layout.titleFont)
        .foregroundStyle(LorvexDesign.Palette.focus)
        .accessibilityHidden(true)
      Text(model.headline)
        .font(layout.titleFont)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private var taskContent: some View {
    if model.taskRows.isEmpty {
      Text(model.subheadline)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(model.taskRows.prefix(effectiveRowLimit)) { row in
          LinkedTaskRowView(
            row: row, interactive: layout.isInteractive, compactActions: layout.compactActions)
        }
      }
    }
  }

  private var effectiveRowLimit: Int {
    layout.rowLimit
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Text(model.focusCountText)
        .font(.caption2.weight(.medium))
      if let attentionCountText = model.attentionCountText {
        Text(attentionCountText)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
      }
      if let staleAgeLabel = model.staleAgeLabel {
        WidgetStaleAgeLabel(staleAgeLabel)
      }
      Spacer(minLength: 8)
      Text(model.statusText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}
