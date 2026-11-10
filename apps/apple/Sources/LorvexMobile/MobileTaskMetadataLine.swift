import LorvexCore
import SwiftUI

/// A task row's metadata in the footnote style: the hand-off marker, the
/// task's time today, its due date (red once overdue, orange when due today or
/// tomorrow), a repeat glyph, then the estimate and up to two tags, joined by
/// dots.
///
/// At standard text sizes it keeps to one line: the marker, the time, and the
/// due date always show, and the estimate and tags drop whole from the end
/// when the line runs out of room. At accessibility sizes, where one line
/// holds only a word or two, every item shows and the line wraps like a
/// sentence, breaking between items after their dots, so a dot always follows
/// the last word of its item and no line starts with one.
struct MobileTaskMetadataLine: View {
  /// The task's hand-off to the assistant, leading the line: neutral while the
  /// assistant holds the task, in the accent once it replied.
  var delegation: LorvexTaskDelegationMarker? = nil
  /// The task's time today ("10:55 AM – 11:55 AM"), leading the line after
  /// the hand-off marker.
  let timeLabel: String?
  /// The time is running now ("Until 12:30 PM"), which tints it the accent color.
  var timeIsRunning: Bool = false
  /// The due date relative to today ("yesterday", "in 4d").
  let dueLabel: String?
  /// Whether the due date has passed, which tints it red.
  let isOverdue: Bool
  /// Whether the due date is today or tomorrow, which tints it orange.
  var isDueSoon: Bool = false
  let repeats: Bool
  /// The estimate, then up to two tags, most important first: on one line the
  /// last of them give way first.
  let calmLabels: [String]
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        wrappingLine
      } else {
        oneLine
      }
    }
    .font(.footnote)
  }

  private var oneLine: some View {
    HStack(spacing: 5) {
      if let delegation {
        // The hand-off leads: whether the assistant holds the task, or has
        // replied and waits on the person, is the first thing to read. It
        // keeps its whole width; the items after it give way first.
        HStack(spacing: 4) {
          Image(systemName: LorvexTaskDelegationMarker.systemImage).accessibilityHidden(true)
          Text(MobileTaskDisplayText.delegation(delegation))
        }
        .foregroundStyle(delegation.tint)
        .fixedSize()
        .layoutPriority(2)
        .accessibilityIdentifier("mobile.task.row.delegation")
      }
      if let timeLabel {
        if delegation != nil { separator }
        // The time leads the task's own facts: on Today it is when the work
        // happens.
        HStack(spacing: 4) {
          Image(systemName: "clock").accessibilityHidden(true)
          Text(verbatim: timeLabel).monospacedDigit()
        }
        .foregroundStyle(timeStyle)
        .layoutPriority(1)
      }
      if let dueLabel {
        if delegation != nil || timeLabel != nil { separator }
        HStack(spacing: 4) {
          Image(systemName: dueSymbol).accessibilityHidden(true)
          Text(verbatim: dueLabel).monospacedDigit()
        }
        .foregroundStyle(dueStyle)
        // The deadline outranks the estimate and tags, which give way first.
        .layoutPriority(1)
      }
      if repeats {
        if delegation != nil || timeLabel != nil || dueLabel != nil { separator }
        Image(systemName: "repeat").foregroundStyle(.secondary).accessibilityHidden(true)
      }
      if !calmLabels.isEmpty {
        // Short of room, the last tags drop whole rather than truncating.
        LorvexWholeLabelsLine(
          calmLabels,
          leadingSeparator: delegation != nil || timeLabel != nil || dueLabel != nil || repeats,
          spacing: 5)
      }
    }
    .lineLimit(1)
  }

  /// Every item as one text. A no-break space ties each glyph to its label
  /// and each dot to the item before it, and a label's own spaces do not
  /// break, so the line breaks at the space after a dot, or inside a label
  /// too long for a line of its own.
  private var wrappingLine: Text {
    var items: [Text] = []
    if let delegation {
      items.append(
        glyphed(LorvexTaskDelegationMarker.systemImage, MobileTaskDisplayText.delegation(delegation))
          .foregroundStyle(delegation.tint))
    }
    if let timeLabel {
      items.append(glyphed("clock", timeLabel).foregroundStyle(timeStyle))
    }
    if let dueLabel {
      items.append(glyphed(dueSymbol, dueLabel).foregroundStyle(dueStyle))
    }
    if repeats {
      items.append(Text(Image(systemName: "repeat")).foregroundStyle(.secondary))
    }
    items += calmLabels.map { Text(verbatim: lorvexUnbreakable($0)).foregroundStyle(.secondary) }
    guard let first = items.first else { return Text(verbatim: "") }
    let dot = Text(verbatim: "\u{00A0}·").foregroundStyle(.tertiary)
    return items.dropFirst().reduce(first) { line, item in Text("\(line)\(dot) \(item)") }
  }

  private func glyphed(_ symbol: String, _ label: String) -> Text {
    let label = Text(verbatim: lorvexUnbreakable(label)).monospacedDigit()
    return Text("\(Image(systemName: symbol))\u{00A0}\(label)")
  }

  private var timeStyle: AnyShapeStyle {
    timeIsRunning ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.secondary)
  }

  private var dueSymbol: String {
    isOverdue ? "clock.badge.exclamationmark" : "calendar"
  }

  private var dueStyle: AnyShapeStyle {
    if isOverdue { return AnyShapeStyle(LorvexDesign.Palette.overdue) }
    return isDueSoon ? AnyShapeStyle(LorvexDesign.Palette.dueSoon) : AnyShapeStyle(.secondary)
  }

  private var separator: some View {
    Text(verbatim: "·").foregroundStyle(.tertiary)
  }
}
