import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// The `accessoryRectangular` Lock Screen family: a small ring beside the lead
/// task's title, its line, and the one task after it. With tasks left but no
/// lead, what is left of the day, worded as long as its line allows, and the
/// top two tasks. The ~72pt tile has room for exactly three lines.
struct AccessoryRectangularWidgetView: View {
  let model: WidgetRenderModel

  var body: some View {
    let metrics = LorvexWidgetViewMetrics.metrics(for: .accessoryRectangular)
    VStack(alignment: .leading, spacing: 3) {
      if let lead = model.lead {
        HStack(spacing: 6) {
          ring(progress: lead.progress)
          // Absolute colors inside the links: a `Link` tints its content
          // with the accent, which would color the title on the Lock Screen.
          link(lead.urlString) {
            Text(lead.title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.primary)
              .lineLimit(1)
              // The title is the user's private content on a Lock Screen /
              // Smart Stack surface; redact it when the device locks.
              .privacySensitive()
          }
          Spacer(minLength: 0)
        }
        if let line = lead.line {
          Text(line)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
        }
        if let next = model.taskRows.first {
          link(next.urlString ?? "") {
            Text([next.metadata, next.title].compactMap { $0 }.joined(separator: "  "))
              .font(.caption2)
              .foregroundStyle(Color.secondary)
              .monospacedDigit()
              .lineLimit(1)
              .privacySensitive()
          }
        }
      } else if model.state != .fallback, model.remainingCount > 0 {
        LorvexFirstFittingLine(
          model.dayLineChoices.isEmpty ? [model.headline] : model.dayLineChoices
        ) {
          Text($0)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
        }
        ForEach(model.taskRows) { row in
          link(row.urlString ?? "") {
            Text([row.metadata, row.title].compactMap { $0 }.joined(separator: "  "))
              .font(.caption2)
              .foregroundStyle(Color.secondary)
              .monospacedDigit()
              .lineLimit(1)
              .privacySensitive()
          }
        }
      } else {
        HStack(spacing: 4) {
          Image(systemName: model.state == .fallback ? "exclamationmark.circle" : "checkmark.circle")
            .imageScale(.small)
            .accessibilityHidden(true)
          Text(model.headline)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 0)
        }
        Text(model.subheadline)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
    // No opaque fill: the accessoryRectangular family renders in the Lock
    // Screen / Smart Stack vibrant material, where an opaque card looks
    // foreign. The entry view's `.containerBackground` provides the backing.
  }

  private func ring(progress: Double) -> some View {
    ZStack {
      Circle().stroke(.tertiary, lineWidth: 2)
      LorvexProgressArc(fraction: progress, style: .primary, lineWidth: 2)
        .widgetAccentable()
    }
    .frame(width: 14, height: 14)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func link(_ urlString: String, @ViewBuilder _ content: () -> some View) -> some View {
    if let url = URL(string: urlString) {
      Link(destination: url) { content() }
    } else {
      content()
    }
  }
}
