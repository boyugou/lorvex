import LorvexCore
import SwiftUI

/// One open task previewed on a Lists catalog card: a small ring, the title on
/// one line, and the task's due day when it has one, in red once it has
/// passed. Clicking it opens the task; the pointer draws a faint fill.
struct ListCatalogPreviewTaskRow: View {
  let task: LorvexTask
  let open: () -> Void

  @State private var isHovering = false
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  var body: some View {
    Button(action: open) {
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        Circle()
          .strokeBorder(.secondary, lineWidth: 1.2)
          .frame(width: 8, height: 8)
          .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
          .accessibilityHidden(true)
        Text(task.title)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: LorvexDesign.Spacing.s)
        if let due = dueLabel {
          Text(due.text)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(due.tint)
            .lineLimit(1)
            .fixedSize()
        }
      }
      .padding(.vertical, 3)
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .background {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
          .fill(LorvexDesign.Palette.hoverFill.opacity(isHovering ? 1 : 0))
      }
      .contentShape(Rectangle())
      // The fill reaches past the text; the negative padding keeps the ring
      // aligned with the list name above.
      .padding(.horizontal, -LorvexDesign.Spacing.s)
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityIdentifier("list.preview.\(task.id)")
  }

  /// "tomorrow", "3d ago": the due day relative to today in the product time
  /// zone, measured from the preview clock when a capture pins it, red once
  /// overdue and orange when due today or tomorrow.
  private var dueLabel: (text: String, tint: AnyShapeStyle)? {
    let now = LorvexPreviewClock.now(in: .current)
    let zone = productTimeZone
    guard let text = task.cachedDueRelativeLabel(now: now, timeZone: zone) else { return nil }
    if task.isOverdue(now: now, timeZone: zone) { return (text, AnyShapeStyle(LorvexDesign.Palette.overdue)) }
    if task.isDueSoon(now: now, timeZone: zone) { return (text, AnyShapeStyle(LorvexDesign.Palette.dueSoon)) }
    return (text, AnyShapeStyle(.secondary))
  }
}
