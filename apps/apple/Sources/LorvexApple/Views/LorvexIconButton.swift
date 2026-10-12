import LorvexCore
import SwiftUI

private enum LorvexIconButtonMetrics {
  static let hitSize: CGFloat = 28
}

/// The app's one icon-only button: a glyph in the secondary style inside a
/// 28-point circular hit area that fills faintly while the pointer is over it.
/// Panel chrome uses it (an inspector's close and pin buttons, a pager's
/// arrows), so every bare icon control has the same size, weight, and hover.
/// `label` is the tooltip and the VoiceOver name; the glyph alone never names
/// the action.
struct LorvexIconButton: View {
  let systemImage: String
  let label: String
  var accessibilityIdentifier: String? = nil
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: LorvexIconButtonMetrics.hitSize, height: LorvexIconButtonMetrics.hitSize)
        .background(Circle().fill(.quaternary.opacity(isHovering ? 1 : 0)))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .reduceMotionAnimation(.easeOut(duration: 0.12), value: isHovering)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier(accessibilityIdentifier ?? "")
  }
}

/// The icon-only menu: the same glyph, hit area, and hover as
/// ``LorvexIconButton``, opening `content`. A menu wears the glyph through the
/// plain button style and no indicator; the system's own menu styles would
/// redraw the label in their colors and add a chevron. `label` is the tooltip
/// and the VoiceOver name.
struct LorvexIconMenu<Content: View>: View {
  let systemImage: String
  let label: String
  var accessibilityIdentifier: String? = nil
  @ViewBuilder let content: () -> Content

  @State private var isHovering = false

  var body: some View {
    Menu(content: content) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: LorvexIconButtonMetrics.hitSize, height: LorvexIconButtonMetrics.hitSize)
        .background(Circle().fill(.quaternary.opacity(isHovering ? 1 : 0)))
        .contentShape(Circle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { isHovering = $0 }
    .reduceMotionAnimation(.easeOut(duration: 0.12), value: isHovering)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier(accessibilityIdentifier ?? "")
  }
}
