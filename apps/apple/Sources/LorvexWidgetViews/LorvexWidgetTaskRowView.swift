import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI

struct WidgetActionButton<Intent: AppIntent>: View {
  let intent: Intent
  let systemName: String
  let accessibilityLabel: String
  var tint: Color = .secondary

  var body: some View {
    Button(intent: intent) {
      Image(systemName: systemName)
        .imageScale(.medium)
        .frame(minWidth: 32, minHeight: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .foregroundStyle(tint)
    .accessibilityLabel(accessibilityLabel)
  }
}

/// The lead task's circle as the widget's Done control: a ring that fills
/// while the task's time runs, an empty circle otherwise. Tapping it completes
/// the task in place through `WidgetCompleteTaskIntent` without opening the
/// app. Home Screen families only; the Lock Screen families draw the ring
/// without the button.
struct WidgetLeadRing: View {
  let lead: WidgetLeadRender
  var diameter: CGFloat = 40

  var body: some View {
    Button(intent: WidgetCompleteTaskIntent(taskID: lead.id, title: lead.title)) {
      LorvexTaskRing(progress: lead.progress, isDone: false, diameter: diameter)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      String(
        localized: "widget.action.complete.a11y",
        defaultValue: "Complete \(lead.title)",
        table: "Localizable",
        bundle: WidgetL10n.bundle))
  }
}

/// The line under the lead task's title, red when it reports a missed
/// deadline.
struct WidgetLeadLine: View {
  let line: String
  let isOverdue: Bool

  var body: some View {
    Text(line)
      .font(.caption2)
      .foregroundStyle(isOverdue ? LorvexDesign.Palette.overdue : Color.secondary)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.8)
  }
}

/// The lead task as the medium and large families draw it: the circle, an
/// optional label over the title, the title (a link into the task), and its
/// line.
struct WidgetLeadBlock: View {
  let lead: WidgetLeadRender
  var label: String?
  var ringDiameter: CGFloat = 40
  var titleFont: Font = .subheadline.weight(.semibold)
  var titleLines: Int = 1

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      WidgetLeadRing(lead: lead, diameter: ringDiameter)
      VStack(alignment: .leading, spacing: 2) {
        if let label {
          Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(LorvexDesign.Palette.accent)
        }
        link(lead.urlString) {
          Text(lead.title)
            .font(titleFont)
            .foregroundStyle(Color.primary)
            .lineLimit(titleLines)
            .multilineTextAlignment(.leading)
            // The title is the user's private content on a Home Screen /
            // StandBy surface; redact it when the device locks.
            .privacySensitive()
        }
        if let line = lead.line {
          WidgetLeadLine(line: line, isOverdue: lead.isOverdue)
        }
      }
      Spacer(minLength: 0)
    }
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

/// One task under the lead: its time, state, or estimate, its title (a link
/// into the task), and, when `interactive`, a circle that completes it.
struct WidgetTaskRowView: View {
  let row: WidgetTaskRenderRow
  var interactive = false
  /// The clock column: wide enough for "11:00 AM" in caption2, and growing
  /// with the text size so a larger size does not cut the time to "11:0…".
  @ScaledMetric(relativeTo: .caption2) var clockColumnWidth: CGFloat = 58

  var body: some View {
    HStack(spacing: 8) {
      rowContent
      if interactive {
        Spacer(minLength: 0)
        WidgetActionButton(
          intent: WidgetCompleteTaskIntent(taskID: row.id, title: row.title),
          systemName: "circle",
          accessibilityLabel: String(
            localized: "widget.action.complete.a11y",
            defaultValue: "Complete \(row.title)",
            table: "Localizable",
            bundle: WidgetL10n.bundle),
          tint: LorvexDesign.Palette.accent
        )
      }
    }
  }

  @ViewBuilder
  private var rowContent: some View {
    if let url = row.url {
      Link(destination: url) { label }
    } else {
      label
    }
  }

  private var label: some View {
    // Absolute colors, not the hierarchical styles: the enclosing `Link` sets
    // the foreground to the accent, so a hierarchical level would resolve to
    // a shade of blue instead of the label colors.
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(row.metadata ?? "")
        .font(.caption2)
        .foregroundStyle(metadataColor)
        .monospacedDigit()
        .lineLimit(1)
        .frame(width: clockColumnWidth, alignment: .leading)
      Text(row.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .privacySensitive()
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel([row.metadata, row.title].compactMap { $0 }.joined(separator: ", "))
  }
}

extension WidgetTaskRowView {
  private var metadataColor: Color {
    switch row.tone {
    case .plain: Color.secondary
    case .running, .started: LorvexDesign.Palette.accent
    case .overdue: LorvexDesign.Palette.overdue
    }
  }
}

extension WidgetTaskRenderRow {
  var url: URL? {
    guard let urlString else { return nil }
    return URL(string: urlString)
  }
}

/// The foot every Home Screen family shares: how many tasks follow the ones
/// on screen, how many got done today, and the stale capsule once the list is
/// old. Says each fact once and stays silent when there is nothing to say.
struct WidgetFootLine: View {
  let model: WidgetRenderModel
  var showsDone = false
  /// The next rows actually drawn, when the view shows fewer than
  /// `model.taskRows` (a larger text size fits fewer); nil means all of them.
  var shownRowCount: Int?

  var body: some View {
    let hidden = model.upcomingCount - (shownRowCount ?? model.taskRows.count)
    HStack(spacing: 8) {
      if hidden > 0 {
        Text(
          String(
            localized: "widget.foot.more_today",
            defaultValue: "\(hidden) more today",
            table: "Localizable",
            bundle: WidgetL10n.bundle)
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
      if showsDone, model.completedCount > 0 {
        Text(
          String(
            localized: "widget.foot.done_today",
            defaultValue: "\(model.completedCount) done today",
            table: "Localizable",
            bundle: WidgetL10n.bundle)
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 0)
      if let staleAgeLabel = model.staleAgeLabel {
        WidgetStaleAgeLabel(staleAgeLabel)
      }
    }
    .lineLimit(1)
  }
}
