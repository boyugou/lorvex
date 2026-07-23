import LorvexCore
import SwiftUI

/// A lightweight in-app toast that displays `message` as a brief pill banner
/// anchored to the bottom of its container. Dismisses automatically after
/// `duration` seconds or when tapped.
struct LorvexToast: ViewModifier {
  let message: String?
  let duration: Double
  let dismiss: () -> Void

  func body(content: Content) -> some View {
    content
      // The toast is a transient overlay that never pulls VoiceOver focus, so
      // its text would otherwise go unspoken. Post an announcement when a new
      // message arrives so assistive tech hears it. Attached to the always-
      // present host content (not the conditional overlay) so the nil→message
      // transition is observed.
      .onChange(of: message) { _, newValue in
        guard let newValue else { return }
        AccessibilityNotification.Announcement(newValue).post()
      }
      .overlay(alignment: .bottom) {
        if let message {
          Text(message)
            .font(LorvexDesign.Typography.secondaryText)
            // `.primary` tracks the system material's light/dark + tint
            // automatically, so the label stays readable across every accent
            // color choice, including light accents like Yellow or Mint.
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // A toast floats over the workspace, so it wears system Liquid Glass on
            // macOS 26 (and a bordered material capsule on earlier releases).
            .lorvexFloatingGlass(in: Capsule())
            .padding(.bottom, 20)
            // Scope animation to the toast-only branch so a `message` change
            // doesn't animate descendant changes in the host content tree.
            .reduceMotionAnimation(.easeInOut(duration: 0.25), value: message)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { dismiss() }
            .task(id: message) {
              try? await Task.sleep(for: .seconds(duration))
              dismiss()
            }
            .accessibilityLabel(message)
            .accessibilityIdentifier("lorvex.toast")
        }
      }
  }
}

extension View {
  /// Overlays an auto-dismissing toast banner driven by an optional message.
  ///
  /// - Parameters:
  ///   - message: The text to display. Pass `nil` to hide the toast.
  ///   - duration: Seconds before the toast auto-dismisses. Defaults to 3.5.
  ///   - dismiss: Called when the toast should be cleared (auto-dismiss or tap).
  func lorvexToast(message: String?, duration: Double = 3.5, dismiss: @escaping () -> Void)
    -> some View
  {
    modifier(LorvexToast(message: message, duration: duration, dismiss: dismiss))
  }
}
