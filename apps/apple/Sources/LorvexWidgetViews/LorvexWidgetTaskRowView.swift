import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI

/// A task row's height at the default text size: the height of its circle's
/// hit target, so rows stack with no gap between them.
let widgetRowHeight: CGFloat = 30

/// A glyph that runs `intent` when tapped, in a hit target a row high and
/// `width` wide (as wide as it is high when `width` is nil), with the glyph
/// placed by `alignment`. The glyph is drawn one image scale up from the
/// row's text, so a task's circle reads as its checkbox. The row's height
/// grows with the row's text, as the glyph does, so at a larger text size the
/// circles keep clear of each other and of the titles beside them.
///
/// The button is `.plain`: on macOS the borderless style is an AppKit control,
/// which WidgetKit cannot draw, so the widget would show its unsupported-view
/// placeholder (a yellow box with a red prohibition sign) in its place.
struct WidgetActionButton<Intent: AppIntent>: View {
  let intent: Intent
  let systemName: String
  let accessibilityLabel: String
  var tint: Color = .secondary
  var width: CGFloat?
  var alignment: Alignment = .center

  @ScaledMetric(relativeTo: WidgetType.rowTextStyle) private var height = widgetRowHeight

  var body: some View {
    Button(intent: intent) {
      Image(systemName: systemName)
        .font(WidgetType.row)
        .imageScale(.large)
        .frame(width: width ?? height, height: height, alignment: alignment)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(tint)
    .widgetAccentable()
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
    .widgetAccentable()
    .accessibilityLabel(
      String(
        localized: "widget.action.complete.a11y",
        defaultValue: "Complete \(lead.title)",
        table: "Localizable",
        bundle: WidgetL10n.bundle))
  }
}

/// The lead task's line ("Until 10:30 AM", "9:45 – 10:30 AM", "Overdue"): in
/// the accent while the task's time runs, as its ring is, red when it reports
/// a missed deadline, and secondary otherwise, the colors a row's time takes.
/// One line, or with `wraps` up to two, the second starting at a space
/// (``WidgetSpaceWrappedText``).
struct WidgetLeadLine: View {
  let lead: WidgetLeadRender
  let line: String
  var wraps = false

  var body: some View {
    Group {
      if wraps {
        WidgetSpaceWrappedText(line)
      } else {
        Text(line).lineLimit(1)
      }
    }
    .font(WidgetType.meta)
    .foregroundStyle(color)
    .monospacedDigit()
  }

  private var color: Color {
    if lead.isOverdue { return LorvexDesign.Palette.overdue }
    return lead.isRunning ? LorvexDesign.Palette.accent : Color.secondary
  }
}

/// The lead task as the medium and large families draw it: the circle, the
/// title (a link into the task), and under it the task's line, led by `label`
/// when one is given ("Today · Until 10:30 AM"), so the title reads first and
/// the label costs no line of its own.
struct WidgetLeadBlock: View {
  let lead: WidgetLeadRender
  var label: String?
  var ringDiameter: CGFloat = 40
  var titleFont: Font = WidgetType.title
  var titleLines: Int = 1

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      WidgetLeadRing(lead: lead, diameter: ringDiameter)
      VStack(alignment: .leading, spacing: 2) {
        link(lead.urlString) {
          Text(userContent: lead.title)
            .font(titleFont)
            .foregroundStyle(Color.primary)
            .lineLimit(titleLines)
            .multilineTextAlignment(.leading)
            // The title is the user's private content on a Home Screen /
            // StandBy surface; redact it when the device locks.
            .privacySensitive()
        }
        if label != nil || lead.line != nil {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let label {
              Text(label)
                .font(WidgetType.label)
                .foregroundStyle(LorvexDesign.Palette.accent)
                .lineLimit(1)
                .fixedSize()
                .widgetAccentable()
            }
            if label != nil, lead.line != nil {
              Text(verbatim: "·")
                .font(WidgetType.meta)
                .foregroundStyle(.tertiary)
            }
            if let line = lead.line {
              WidgetLeadLine(lead: lead, line: line)
            }
          }
        }
      }
      // A frame rather than a trailing spacer, whose stack spacing would
      // truncate the title 12 points early.
      .frame(maxWidth: .infinity, alignment: .leading)
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

/// One task under the lead: a circle that completes it, tinted by the task's
/// priority, its title (a link into the task), and its time, state, or
/// estimate at the trailing edge, as the app's task rows read.
///
/// Under a lead task the circle sits centered in a column as wide as the lead
/// ring (`leadRingDiameter`), so the circles share the ring's axis and the
/// titles start where the lead's title does. Without a lead the circle sits
/// at the leading edge, in line with the header's text, and its hit target
/// spans the gap to the title.
struct WidgetTaskRowView: View {
  let row: WidgetTaskRenderRow
  var leadRingDiameter: CGFloat?

  var body: some View {
    // 12pt after a lead-width column is the lead block's ring-to-title gap.
    HStack(spacing: leadRingDiameter == nil ? 0 : 12) {
      WidgetActionButton(
        intent: WidgetCompleteTaskIntent(taskID: row.id, title: row.title),
        systemName: "circle",
        accessibilityLabel: String(
          localized: "widget.action.complete.a11y",
          defaultValue: "Complete \(row.title)",
          table: "Localizable",
          bundle: WidgetL10n.bundle),
        tint: (row.priority ?? .p3).priorityTint,
        width: leadRingDiameter,
        alignment: leadRingDiameter == nil ? .leading : .center
      )
      rowContent
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
      Text(row.title)
        .font(WidgetType.row)
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .privacySensitive()
      Spacer(minLength: 0)
      if let metadata = row.metadata {
        Text(metadata)
          .font(WidgetType.meta)
          .foregroundStyle(metadataColor)
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize()
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel([row.title, row.metadata].compactMap { $0 }.joined(separator: ", "))
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
/// on screen and how many got done today, as one line of facts, and the stale
/// capsule once the list is old. Says each fact once and stays silent when
/// there is nothing to say.
struct WidgetFootLine: View {
  let model: WidgetRenderModel
  var showsDone = false
  /// The next rows actually drawn, when the view shows fewer than
  /// `model.taskRows` (a larger text size fits fewer); nil means all of them.
  var shownRowCount: Int?

  var body: some View {
    HStack(spacing: 8) {
      if let facts {
        Text(facts)
          .font(WidgetType.foot)
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 0)
      if let staleAgeLabel = model.staleAgeLabel {
        WidgetStaleAgeLabel(staleAgeLabel)
      }
    }
    .lineLimit(1)
  }

  /// "4 more today · 2 done today", either fact alone, or nil.
  private var facts: String? {
    let hidden = model.upcomingCount - (shownRowCount ?? model.taskRows.count)
    var facts: [String] = []
    if hidden > 0 {
      facts.append(
        String(
          localized: "widget.foot.more_today",
          defaultValue: "\(hidden) more today",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
    }
    if showsDone, model.completedCount > 0 {
      facts.append(
        String(
          localized: "widget.foot.done_today",
          defaultValue: "\(model.completedCount) done today",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
    }
    return facts.isEmpty ? nil : facts.joined(separator: " · ")
  }
}
