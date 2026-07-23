import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

struct AccessoryRectangularWidgetView: View {
  let model: WidgetRenderModel

  var body: some View {
    let metrics = LorvexWidgetViewMetrics.metrics(for: .accessoryRectangular)
    VStack(alignment: .leading, spacing: 3) {
      // Compact header folds the focus count into the title ("Focus · 3 in
      // focus"); the ~72pt Lock Screen tile has no room for a separate status
      // badge and a standalone count line (they overlapped the first task row).
      HStack(spacing: 4) {
        Image(systemName: "scope")
          .imageScale(.small)
          .accessibilityHidden(true)
        Text(headerText)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      if model.taskRows.isEmpty {
        Text(model.subheadline)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      } else {
        ForEach(model.taskRows.prefix(metrics.maxVisibleRows)) { row in
          if let url = row.url {
            Link(destination: url) {
              AccessoryRectangularTaskRow(row: row)
            }
          } else {
            AccessoryRectangularTaskRow(row: row)
          }
        }
      }
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
    // No opaque fill: the accessoryRectangular family renders in the Lock
    // Screen / Smart Stack vibrant material, where an opaque card looks
    // foreign. The entry view's `.containerBackground` provides the backing.
  }

  private var headerText: String {
    // Fold the focus count into the title ("Focus · 3 in focus"), but drop it
    // when nothing is in focus so the empty state reads "Focus", not the
    // self-contradictory "Focus · 0 in focus".
    guard model.focusCount > 0, !model.focusCountText.isEmpty else { return model.headline }
    return "\(model.headline) · \(model.focusCountText)"
  }
}

private struct AccessoryRectangularTaskRow: View {
  let row: WidgetTaskRenderRow

  var body: some View {
    HStack(alignment: .top, spacing: 5) {
      WidgetPriorityDot(color: row.priorityTintColor, fallback: .secondary, topPadding: 3)
      Text(row.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        // The task title is the user's private content on a Lock Screen / Smart
        // Stack surface; redact it when the device locks.
        .privacySensitive()
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      [row.priorityLabel, row.title].compactMap { $0 }.joined(separator: ", "))
  }
}
