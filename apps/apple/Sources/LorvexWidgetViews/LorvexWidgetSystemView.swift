import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

enum SystemWidgetLayout {
  case medium
  case large

  /// As tall as the lead's title and line together on medium, so the block
  /// is no taller than its text and two rows fit under it.
  var ringDiameter: CGFloat {
    switch self {
    case .medium: 40
    case .large: 52
    }
  }

  var titleFont: Font {
    switch self {
    case .medium: WidgetType.title
    case .large: WidgetType.display
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
/// to complete it on the lead ring's axis. With tasks left but no lead, the
/// widget's title and a line saying what is left of the day take the lead's
/// place and the list starts at its top. Large opens with the title and the
/// assistant's briefing in its serif voice, and closes with how much got done
/// today. The briefing keeps up to three lines, whole where it fits them; the
/// rows are as many as the height left holds, and the ones that give way (to
/// the briefing or to a larger text size) are counted by the foot line's "N
/// more today" instead of the foot line being clipped. Under its tasks, large
/// lists the day's calendar events still ahead, which give way to the first
/// two tasks but not to the ones after them.
struct SystemWidgetView: View {
  let model: WidgetRenderModel
  let layout: SystemWidgetLayout

  /// The most rows the view draws: the largest row budget of a family it
  /// draws (``WidgetFamilyKind/maxTaskRowsWithoutLead`` of `systemLarge`).
  /// The rows are static branches up to this count, never a `ForEach`.
  static let rowCapacity = 7

  /// The most event rows the view draws: ``WidgetFamilyKind/maxEventRows``
  /// of `systemLarge`, drawn as static branches like the task rows.
  static let eventCapacity = 3

  var body: some View {
    let metrics = LorvexWidgetViewMetrics.metrics(for: model.family)
    VStack(alignment: .leading, spacing: 6) {
      if model.state == .fallback {
        unavailable
      } else if model.lead != nil || model.remainingCount > 0 {
        leadContent(model.lead, briefing: metrics.showsBriefing ? model.briefing : nil)
      } else {
        allClear
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetTypesetting()
    // No padding and no opaque fill: the view draws inside WidgetKit's content
    // margins, and the entry view's `.containerBackground` supplies the
    // widget's backing material.
  }

  /// The lead task's page: on large the title and the briefing, when there is
  /// one; then the lead block (or, with no lead, what is left of the day) and,
  /// under it, as many rows as fit with the foot line.
  private func leadContent(_ lead: WidgetLeadRender?, briefing: String?) -> some View {
    // 4pt between the blocks on large, whose height decides whether its last
    // row fits; the rows' own height already sets them off the lead.
    VStack(alignment: .leading, spacing: layout == .large ? 4 : 6) {
      if layout == .large {
        VStack(alignment: .leading, spacing: 2) {
          label
          if let briefing {
            // The assistant's note on the day is the user's private content;
            // redact it when the device locks.
            Text(briefing, serifVoice: .widgetBriefing)
              .userContentTypesetting(briefing)
              .foregroundStyle(.secondary)
              .lineLimit(3)
              .fixedSize(horizontal: false, vertical: true)
              .privacySensitive()
          }
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
      // The candidates, most rows first, are static, as the rows in each
      // are: SwiftUI may evaluate a candidate it does not draw off the main
      // thread, where a `ForEach` content closure trips Swift 6's isolation
      // check. Counts below zero draw no rows, so the last candidates repeat.
      let rowCount = model.taskRows.count
      let events = model.eventRows.count
      ViewThatFits(in: .vertical) {
        if events > 0 {
          // The day's events stay while two tasks fit above them: tasks past
          // the second give way first, counted by the foot line, since an
          // event is a fixed commitment and those tasks come later in
          // Today's order. Then the events give way, one and then all.
          let kept = min(rowCount, 2)
          nextRowsAndFoot(showing: rowCount, events: events)
          nextRowsAndFoot(showing: max(kept, rowCount - 1), events: events)
          nextRowsAndFoot(showing: max(kept, rowCount - 2), events: events)
          nextRowsAndFoot(showing: max(kept, rowCount - 3), events: events)
          nextRowsAndFoot(showing: max(kept, rowCount - 4), events: events)
          nextRowsAndFoot(showing: max(kept, rowCount - 5), events: events)
          nextRowsAndFoot(showing: kept, events: events - 1)
          nextRowsAndFoot(showing: kept, events: 1)
        }
        nextRowsAndFoot(showing: rowCount)
        nextRowsAndFoot(showing: rowCount - 1)
        nextRowsAndFoot(showing: rowCount - 2)
        nextRowsAndFoot(showing: rowCount - 3)
        nextRowsAndFoot(showing: rowCount - 4)
        nextRowsAndFoot(showing: rowCount - 5)
        nextRowsAndFoot(showing: rowCount - 6)
        nextRowsAndFoot(showing: rowCount - 7)
      }
    }
  }

  /// The widget's name: "Today", or the list a configured widget shows.
  private var label: some View {
    Text(model.headline)
      .font(WidgetType.label)
      .foregroundStyle(LorvexDesign.Palette.accent)
      .lineLimit(1)
      .widgetAccentable()
  }

  /// The first `requested` rows (none when it is zero or less) and the foot
  /// line under them. Gaps are explicit paddings rather than stack spacing,
  /// so the zero-height spacer adds none: `ViewThatFits` measures this at its
  /// natural height, and on medium two rows fit with only a few points to
  /// spare. The rows need no gap between them; each is as tall as its
  /// complete button.
  private func nextRowsAndFoot(showing requested: Int, events requestedEvents: Int = 0) -> some View {
    let count = max(0, min(requested, model.taskRows.count, Self.rowCapacity))
    let events = max(0, min(requestedEvents, model.eventRows.count, Self.eventCapacity))
    return VStack(alignment: .leading, spacing: 0) {
      taskRow(0, shownRowCount: count)
      taskRow(1, shownRowCount: count)
      taskRow(2, shownRowCount: count)
      taskRow(3, shownRowCount: count)
      taskRow(4, shownRowCount: count)
      taskRow(5, shownRowCount: count)
      taskRow(6, shownRowCount: count)
      if events > 0 {
        // The events open a block of their own, set off from the tasks
        // above by a gap rather than a rule.
        VStack(alignment: .leading, spacing: 0) {
          eventRow(0, shownEventCount: events)
          eventRow(1, shownEventCount: events)
          eventRow(2, shownEventCount: events)
        }
        .padding(.top, count > 0 ? 6 : 0)
      }
      Spacer(minLength: 0)
      WidgetFootLine(model: model, showsDone: layout == .large, shownRowCount: count)
        .padding(.top, 2)
    }
  }

  @ViewBuilder
  private func eventRow(_ index: Int, shownEventCount: Int) -> some View {
    if index < shownEventCount {
      WidgetEventRowView(
        row: model.eventRows[index],
        leadRingDiameter: model.lead == nil ? nil : layout.ringDiameter)
    }
  }

  @ViewBuilder
  private func taskRow(_ index: Int, shownRowCount: Int) -> some View {
    if index < shownRowCount {
      WidgetTaskRowView(
        row: model.taskRows[index],
        leadRingDiameter: model.lead == nil ? nil : layout.ringDiameter)
    }
  }

  /// The lead's place when no task leads: on medium the title, then what is
  /// left of the day (large shows its title above the briefing).
  private var dayHeader: some View {
    VStack(alignment: .leading, spacing: 2) {
      if layout == .medium {
        label
      }
      if let dayLine = model.dayLineUnderTitle {
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
          .font(WidgetType.title)
          .foregroundStyle(LorvexDesign.Palette.done)
          .widgetAccentable()
          .accessibilityHidden(true)
        Text("widget.small.all_clear", bundle: WidgetL10n.bundle)
          .font(WidgetType.title)
          .foregroundStyle(Color.primary)
      }
      Text(model.subheadline)
        .font(WidgetType.row)
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
        .font(WidgetType.meta)
        .foregroundStyle(Color.secondary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
      Text(model.statusText)
        .font(WidgetType.foot)
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
    }
  }
}
