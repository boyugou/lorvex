import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// The `systemSmall` Today widget: the lead task alone — its circle (the Done
/// control, a filling ring while its time runs) beside the line that says
/// when it is, its title under them, and one quiet line saying how many tasks
/// follow. The ring and its line lead because the ring draws the task's time
/// and the line names it. With tasks left but no lead, the widget's title,
/// what is left of the day, and the top tasks with their circles. Tapping
/// anywhere else opens Today through the entry view's `widgetURL`.
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // No padding and no opaque fill: the view draws inside WidgetKit's content
    // margins, and the entry view's `.containerBackground` supplies the
    // widget's backing material.
  }

  /// The lead's page, with the foot line where the title keeps its lines
  /// beside it; at a text size where it does not, the foot line gives way
  /// before the title does.
  private func content(_ lead: WidgetLeadRender) -> some View {
    ViewThatFits(in: .vertical) {
      leadPage(lead, showsFoot: true)
      leadPage(lead, showsFoot: false)
    }
  }

  /// The ring and its line, the title under them, then the foot line pinned
  /// to the bottom. The spacer sits outside the spaced stack so it adds no
  /// gaps of its own: the title needs that room for its third line. The ring's
  /// row has no trailing spacer, whose stack spacing would cost the line the
  /// width a time range needs to stay on one line.
  private func leadPage(_ lead: WidgetLeadRender, showsFoot: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          WidgetLeadRing(lead: lead, diameter: 36)
          if let line = lead.line {
            WidgetLeadLine(lead: lead, line: line, wraps: true)
          }
        }
        Text(userContent: lead.title)
          .font(WidgetType.title)
          .foregroundStyle(Color.primary)
          .lineLimit(3)
          // The title is the user's private content on a Home Screen / StandBy
          // surface; redact it when the device locks.
          .privacySensitive()
      }
      Spacer(minLength: 0)
      if showsFoot {
        WidgetFootLine(model: model)
      }
    }
  }

  /// Tasks left, none leading: the widget's name with the work left at its
  /// trailing edge, as the Habits widget carries its count, then the top
  /// tasks, each with its circle and a title of up to two lines, and the foot
  /// line counting the rest. The rows drop their metadata column, which the
  /// small tile is too narrow for, and the day's count, which the rows and the
  /// foot line already say: on an iPhone's small tile a title on one line kept
  /// about eight characters. The work gives way where it and the name do not
  /// fit one line (a long list name, a larger text size), since the name says
  /// which widget this is. Where two rows of two lines do not fit (a larger
  /// text size, a script with tall lines), one row is shown, its title on two
  /// lines and then on one, and the foot line counts the rest: one readable
  /// title beats two cut to a word.
  private var dayContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          nameLabel
          Spacer(minLength: 0)
          if let dayWork = model.dayWork {
            Text(dayWork)
              .font(WidgetType.meta)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        nameLabel
      }
      ViewThatFits(in: .vertical) {
        rowsAndFoot(showing: min(2, model.taskRows.count), titleLines: 2)
        rowsAndFoot(showing: min(1, model.taskRows.count), titleLines: 2)
        rowsAndFoot(showing: min(1, model.taskRows.count), titleLines: 1)
        rowsAndFoot(showing: 0, titleLines: 1)
      }
      .padding(.top, 4)
    }
  }

  /// The widget's name: "Today", or the list a configured widget shows.
  private var nameLabel: some View {
    Text(model.headline)
      .font(WidgetType.label)
      .foregroundStyle(LorvexDesign.Palette.accent)
      .lineLimit(1)
      .widgetAccentable()
  }

  /// Static branches rather than `ForEach`: each candidate of the
  /// `ViewThatFits` above may be evaluated off the main thread, where a
  /// `ForEach` content closure trips Swift 6's isolation check.
  private func rowsAndFoot(showing count: Int, titleLines: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if count > 0, let first = model.taskRows.first {
        SmallTaskRow(row: first, titleLines: titleLines)
      }
      if count > 1, model.taskRows.count > 1 {
        // A title on two lines fills its row, so the next row keeps a gap to
        // read as another task.
        SmallTaskRow(row: model.taskRows[1], titleLines: titleLines)
          .padding(.top, titleLines > 1 ? 4 : 0)
      }
      Spacer(minLength: 0)
      WidgetFootLine(model: model, shownRowCount: count)
    }
  }

  /// Nothing left: the seal where the lead's ring stands, "All clear" where
  /// its title does, and at the foot how many tasks got done today.
  private var allClear: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "checkmark.seal.fill")
        .font(.title)
        .foregroundStyle(LorvexDesign.Palette.done)
        .widgetAccentable()
      Text("widget.small.all_clear", bundle: WidgetL10n.bundle)
        .font(WidgetType.title)
        .foregroundStyle(Color.primary)
      Spacer(minLength: 0)
      WidgetFootLine(model: model, showsDone: true)
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
        .font(WidgetType.meta)
        .foregroundStyle(Color.secondary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// A row of the small widget: the task's circle, which completes it, and its
/// title of up to `titleLines` lines, a link into the task. No metadata
/// column; the tile is too narrow.
private struct SmallTaskRow: View {
  let row: WidgetTaskRenderRow
  let titleLines: Int
  @LorvexDifferentiateWithoutColor private var differentiateWithoutColor
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    // The circle stands beside the title's first line, as a checkbox does.
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      WidgetActionButton(
        intent: WidgetCompleteTaskIntent(taskID: row.id, title: row.title),
        systemName: WidgetPriorityMarking.circleGlyph(
          row.priority, differentiateWithoutColor: differentiateWithoutColor,
          renderingMode: renderingMode),
        accessibilityLabel: String(
          localized: "widget.action.complete.a11y",
          defaultValue: "Complete \(row.title)",
          table: "Localizable",
          bundle: WidgetL10n.bundle),
        tint: WidgetPriorityMarking.tint(row.priority),
        alignment: .leading)
      title
    }
  }

  @ViewBuilder
  private var title: some View {
    let text = Text(row.title)
      .font(WidgetType.row)
      .foregroundStyle(Color.primary)
      .lineLimit(titleLines)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .privacySensitive()
    if let url = row.url {
      Link(destination: url) { text }
    } else {
      text
    }
  }
}
