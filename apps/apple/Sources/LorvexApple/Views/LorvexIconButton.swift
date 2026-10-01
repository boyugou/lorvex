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
    .animation(.easeOut(duration: 0.12), value: isHovering)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier(accessibilityIdentifier ?? "")
  }
}
