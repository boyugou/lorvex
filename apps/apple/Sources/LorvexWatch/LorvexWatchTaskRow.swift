import LorvexCore
import SwiftUI

/// One of Today's tasks on the wrist: the circle that completes it, its title,
/// and one line about it (``LorvexWatchTaskLine``). Tapping the title opens the
/// task's actions.
struct LorvexWatchTaskRow: View {
  let task: LorvexTask
  let line: LorvexWatchTaskLine?
  let canComplete: Bool
  let complete: () async -> Bool
  let openActions: () -> Void
  @LorvexDifferentiateWithoutColor private var differentiateWithoutColor

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      LorvexWatchCompleteButton(
        title: task.title,
        style: .circle(
          tint: task.priority.priorityTint,
          glyph: task.priority.circleGlyph(differentiating: differentiateWithoutColor)),
        isEnabled: canComplete, complete: complete)
      Button(action: openActions) {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(userContent: task.title)
            .font(LorvexDesign.Typography.primaryText)
            .lineLimit(2)
          if let line {
            Text(line.text)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(line.tone.color)
              .monospacedDigit()
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint(LorvexWatchCalmCopy.actionsHint)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("watch.task.\(task.id)")
  }
}
