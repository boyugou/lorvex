import AppKit
import LorvexCore
import SwiftUI

/// The image that follows the pointer while tasks are dragged: one compact pill
/// with the dragged task's title, and a count badge when the drag carries a
/// multi-task selection. A pill stays readable at any pane width, where a
/// snapshot of the full row would trail across half the window.
struct TaskDragPreview: View {
  /// The title of the row the drag started from.
  let title: String
  /// How many tasks the drag carries, the dragged row included.
  let count: Int

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "circle")
        .foregroundStyle(.secondary)
      Text(userContent: title)
        .lineLimit(1)
      if count > 1 {
        Text(count, format: .number)
          .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
          .padding(.horizontal, LorvexDesign.Spacing.sm)
          .background(.tint, in: Capsule())
      }
    }
    .font(LorvexDesign.Typography.primaryText)
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .frame(maxWidth: 320, alignment: .leading)
    // A solid fill, not a material: the drag image is drawn on its own, without
    // the content under the pointer to blur, so a material would leave the title
    // floating over whatever the drag passes.
    .background(
      Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m)
    )
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.m)
        .strokeBorder(.separator, lineWidth: 1)
    }
    .accessibilityHidden(true)
  }
}
