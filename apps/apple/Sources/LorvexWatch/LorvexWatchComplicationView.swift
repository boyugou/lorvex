import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// Renders a `LorvexWatchComplicationEntry` across supported watch families.
///
/// Every family renders a next-task variant tuned to its size constraints.
///
/// - `.accessoryCircular`: the remaining focus count.
/// - `.accessoryRectangular`: priority dot + task title + status.
/// - `.accessoryInline`: one-liner showing status.
/// - `.accessoryCorner` (watchOS): icon + label.
public struct LorvexWatchComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: LorvexWatchComplicationEntry

  public init(entry: LorvexWatchComplicationEntry) {
    self.entry = entry
  }

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

  enum CircularContent: Equatable {
    case unavailable
    case empty
    case remaining(Int)
  }

  nonisolated static func circularContent(for entry: LorvexWatchComplicationEntry)
    -> CircularContent
  {
    switch entry.availability {
    case .unavailable: .unavailable
    case .empty: .empty
    case .content:
      entry.openFocusCount > 0 ? .remaining(entry.openFocusCount) : .empty
    }
  }

  @ViewBuilder
  private var circularBody: some View {
    switch Self.circularContent(for: entry) {
    case .unavailable:
      Image(systemName: "exclamationmark.circle")
        .accessibilityLabel(entry.statusText)
    case .empty:
      Image(systemName: "scope")
        .accessibilityLabel(entry.statusText)
    case .remaining(let count):
      Text("\(count)")
        .font(.title2.monospacedDigit().weight(.bold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          String(
            localized: "watch.complication.circular.a11y", defaultValue: "\(count) focus tasks",
            table: "Localizable", bundle: WatchL10n.bundle))
    }
  }

  @ViewBuilder
  private var rectangularBody: some View {
    if entry.availability == .unavailable {
      Label(entry.statusText, systemImage: "exclamationmark.circle")
        .font(.body)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
    } else {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          priorityDot
          Text(
            entry.taskTitle
              ?? String(
                localized: "watch.complication.no_focus_task", defaultValue: "No focus task",
                table: "Localizable", bundle: WatchL10n.bundle)
          )
          .font(.body)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .truncationMode(.tail)
          // The task title is the user's private content on an always-on
          // complication; redact it when the watch locks (status stays visible).
          .privacySensitive(entry.taskTitle != nil)
        }
        Text(entry.statusText)
          .font(.caption)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .truncationMode(.tail)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// The primary task's priority dot. Carries its own short accessibility
  /// label ("Priority 1") rather than folding into a combined row label, so
  /// the privacy-sensitive title text keeps its own redact-on-lock behavior.
  @ViewBuilder
  private var priorityDot: some View {
    if let tint = priorityTint {
      Circle()
        .fill(tint)
        .frame(width: 6, height: 6)
        .accessibilityLabel(priorityAccessibilityLabel ?? "")
    }
  }

  private var priorityTint: Color? {
    entry.primaryPriorityTier.flatMap(LorvexTask.Priority.init(tier:)).map(\.priorityTint)
  }

  private var priorityAccessibilityLabel: String? {
    switch entry.primaryPriorityTier {
    case 1:
      String(
        localized: "widget.task.priority.p1", defaultValue: "Priority 1",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    case 2:
      String(
        localized: "widget.task.priority.p2", defaultValue: "Priority 2",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    case 3:
      String(
        localized: "widget.task.priority.p3", defaultValue: "Priority 3",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    default: nil
    }
  }

  private var inlineBody: some View {
    Label(
      entry.statusText,
      systemImage: entry.availability == .unavailable ? "exclamationmark.circle" : "scope")
  }

  #if os(watchOS)
    private var cornerBody: some View {
      ZStack {
        Image(systemName: entry.availability == .unavailable ? "exclamationmark.circle" : "scope")
      }
      .widgetLabel {
        Text(entry.taskTitle ?? entry.statusText)
          .lineLimit(1)
          // The task title is the user's private content; redact on lock.
          .privacySensitive(entry.taskTitle != nil)
      }
    }
  #endif

}
