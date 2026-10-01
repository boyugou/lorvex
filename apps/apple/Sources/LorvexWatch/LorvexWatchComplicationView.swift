import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// Renders a `LorvexWatchComplicationEntry` on the watch face, the way the
/// Lock Screen widget reads the same day.
///
/// - `.accessoryCircular`: the running lead's ring with its minutes left, else
///   how many tasks are left today.
/// - `.accessoryRectangular`: the lead's title and line, and the task after it.
/// - `.accessoryInline`: the lead's short line and title on one line.
/// - `.accessoryCorner` (watchOS): how many tasks are left, with the lead's
///   title along the corner.
///
/// A snapshot that could not be read shows an unavailable glyph and the
/// reason; nothing left shows a checkmark. Task titles are private content on
/// an always-on face, so they redact when the watch locks.
public struct LorvexWatchComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: LorvexWatchComplicationEntry

  public init(entry: LorvexWatchComplicationEntry) {
    self.entry = entry
  }

  private var model: WidgetRenderModel { entry.model }

  public var body: some View {
    Group {
      switch family {
      case .accessoryCircular:
        circularBody
      case .accessoryRectangular:
        rectangularBody
      case .accessoryInline:
        inlineBody
      #if os(watchOS)
        case .accessoryCorner:
          cornerBody
      #endif
      default:
        inlineBody
      }
    }
    .redacted(reason: entry.isPlaceholder ? .placeholder : [])
  }

  // MARK: - Family layouts

  @ViewBuilder
  private var circularBody: some View {
    switch model.circularContent {
    case .unavailable:
      Image(systemName: "exclamationmark.circle")
        .widgetAccentable()
        .accessibilityLabel(model.statusText)
    case .empty:
      Image(systemName: "checkmark")
        .widgetAccentable()
        .accessibilityLabel(Self.allClear)
    case .running(let minutesLeft):
      ring(progress: model.lead?.progress ?? 0) {
        VStack(spacing: -2) {
          Text("\(minutesLeft)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .monospacedDigit()
          Text(
            String(
              localized: "watch.complication.min", defaultValue: "min", table: "Localizable",
              bundle: WatchL10n.bundle)
          )
          .font(.caption2)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        String(
          localized: "watch.complication.running.a11y", defaultValue: "\(minutesLeft) min left",
          table: "Localizable", bundle: WatchL10n.bundle))
    case .remaining(let count):
      ring(progress: 0) {
        VStack(spacing: -2) {
          Text("\(count)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .monospacedDigit()
          Text(
            String(
              localized: "watch.complication.left", defaultValue: "left", table: "Localizable",
              bundle: WatchL10n.bundle)
          )
          .font(.caption2)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Self.remainingLabel(count))
    }
  }

  @ViewBuilder
  private var rectangularBody: some View {
    if model.state == .fallback {
      Label(model.statusText, systemImage: "exclamationmark.circle")
        .font(.body)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else if let lead = model.lead {
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 5) {
          ring(progress: lead.progress, lineWidth: 2) { EmptyView() }
            .frame(width: 13, height: 13)
            .accessibilityHidden(true)
          Text(lead.title)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .privacySensitive()
        }
        if let line = lead.line {
          Text(line)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
        }
        if let next = model.taskRows.first {
          Text([next.metadata, next.title].compactMap { $0 }.joined(separator: "  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .privacySensitive()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else if model.remainingCount > 0 {
      VStack(alignment: .leading, spacing: 1) {
        Text(model.dayLine ?? model.headline)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        ForEach(model.taskRows) { row in
          Text([row.metadata, row.title].compactMap { $0 }.joined(separator: "  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .privacySensitive()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Label(Self.allClear, systemImage: "checkmark.circle")
          .font(.headline)
        Text(model.subheadline)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var inlineBody: some View {
    if model.state == .fallback {
      Label(model.statusText, systemImage: "exclamationmark.circle")
    } else if let lead = model.lead {
      // The fact first, the way the Calendar inline leads with its time, so a
      // long title truncates before the fact does.
      Label(
        [lead.shortLine, lead.title].compactMap { $0 }.joined(separator: " · "),
        systemImage: lead.isOverdue ? "exclamationmark.circle" : "circle"
      )
      .privacySensitive()
    } else if model.remainingCount > 0, let dayLine = model.dayLine {
      Label(dayLine, systemImage: "list.bullet")
    } else {
      Label(Self.allClear, systemImage: "checkmark.circle")
    }
  }

  #if os(watchOS)
    @ViewBuilder
    private var cornerBody: some View {
      switch model.circularContent {
      case .unavailable:
        Image(systemName: "exclamationmark.circle")
          .widgetAccentable()
          .widgetLabel { Text(model.statusText) }
      case .empty:
        Image(systemName: "checkmark")
          .widgetAccentable()
          .widgetLabel { Text(Self.allClear) }
      case .running, .remaining:
        Text("\(model.remainingCount)")
          .font(.system(.headline, design: .rounded).weight(.bold))
          .monospacedDigit()
          .widgetAccentable()
          .accessibilityLabel(Self.remainingLabel(model.remainingCount))
          .widgetLabel {
            if let lead = model.lead {
              Text(lead.title)
                .privacySensitive()
            } else {
              Text(model.dayLine ?? "")
            }
          }
      }
    }
  #endif

  /// A faint track and an accentable arc that starts at the top, like the
  /// app's task ring.
  private func ring(
    progress: Double, lineWidth: CGFloat = 3, @ViewBuilder _ center: () -> some View
  ) -> some View {
    ZStack {
      Circle()
        .stroke(.tertiary, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: progress)
        .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .widgetAccentable()
      center()
        .widgetAccentable()
    }
    .padding(lineWidth >= 3 ? 2 : 0)
  }

  private static var allClear: String {
    String(localized: "watch.today.all_clear", defaultValue: "All clear", table: "Localizable", bundle: WatchL10n.bundle)
  }

  private static func remainingLabel(_ count: Int) -> String {
    String(
      localized: "watch.complication.remaining.a11y", defaultValue: "\(count) tasks left today",
      table: "Localizable", bundle: WatchL10n.bundle)
  }
}
