import LorvexCore
import SwiftUI

/// The leading ring a task carries on the phone's calendar grid, in a timed
/// block or an all-day pill: the same checkbox a task row carries, so a task
/// is completed from the calendar with one tap. A done task shows the filled
/// ring with its check. `font` sizes the glyph to its host (a block's
/// secondary text, a pill's tertiary line); the ring keeps the glyph's own
/// height, so it sits on the baseline of the title beside it.
struct MobileCalendarTaskRing: View {
  let isDone: Bool
  let font: Font
  let width: CGFloat
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
        .font(font.weight(.medium))
        .foregroundStyle(LorvexDesign.Palette.accent.opacity(isDone ? 0.7 : 0.85))
        .frame(width: width)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// What a task on the phone's calendar grid carries beyond the shared task
/// actions (``MobileTaskActionCopy``), in a timed block or an all-day pill:
/// the action that opens it, and the glyph of the one that completes an open
/// task or reopens a done one.
enum MobileCalendarTaskCopy {
  static var open: String {
    String(
      localized: "calendar.task.open", defaultValue: "Open Task", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static func toggleSystemImage(isDone: Bool) -> String {
    isDone ? "arrow.uturn.backward.circle" : "checkmark.circle"
  }
}
