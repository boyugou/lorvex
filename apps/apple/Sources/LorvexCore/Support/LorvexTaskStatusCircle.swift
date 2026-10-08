import SwiftUI

/// A task's leading status circle: its glyph in its color
/// (``LorvexTask/statusCircleGlyph``, ``LorvexTask/statusCircleStyle``), with an
/// open task's priority also marked inside the ring while Differentiate Without
/// Color is on (``LorvexTask/statusCircleGlyph(differentiatingPriority:)``). The
/// view reads that setting itself instead of taking it from its row, so a row
/// that skips redraws while its values are equal still follows a change of the
/// setting.
///
/// It draws like an `Image` of the symbol: the caller sizes it with `font` and
/// `imageScale`, animates glyph changes with `contentTransition`, and makes the
/// tappable frame around it. With `isCompleting` it shows the filled check in
/// the done color that a completion lands on, before the task has resolved.
public struct LorvexTaskStatusCircle: View {
  public var task: LorvexTask
  public var isCompleting: Bool
  @LorvexDifferentiateWithoutColor private var differentiateWithoutColor

  public init(task: LorvexTask, isCompleting: Bool = false) {
    self.task = task
    self.isCompleting = isCompleting
  }

  public var body: some View {
    Image(
      systemName: isCompleting
        ? "checkmark.circle.fill"
        : task.statusCircleGlyph(differentiatingPriority: differentiateWithoutColor)
    )
    .foregroundStyle(isCompleting ? AnyShapeStyle(LorvexDesign.Palette.done) : task.statusCircleStyle)
  }
}
