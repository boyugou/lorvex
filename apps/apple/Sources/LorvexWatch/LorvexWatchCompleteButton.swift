import LorvexCore
import SwiftUI

#if os(watchOS)
  import WatchKit
#endif

/// A task's completion control on the wrist. Tapping it fills it green with a
/// check and completes the task once that lands (300 ms), so the row does not
/// vanish under the finger; the success haptic follows, or the failure one if
/// the action could not be sent. A row draws the circle in its priority tint;
/// a running lead draws its ring, which fills as the task's time passes.
struct LorvexWatchCompleteButton: View {
  enum Style {
    case circle(tint: Color)
    case ring(progress: Double, diameter: CGFloat)
  }

  let title: String
  let style: Style
  let isEnabled: Bool
  /// Completes the task and reports whether the action went through.
  let complete: () async -> Bool
  @State private var isCompleting = false

  var body: some View {
    Button(action: trigger) {
      switch style {
      case .circle(let tint):
        Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isCompleting ? LorvexDesign.Palette.done : tint)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: 28, height: 28)
          // The glyph stays row-sized; the tap target reaches the 44 pt the
          // wrist needs.
          .contentShape(.interaction, Circle().inset(by: -8))
      case .ring(let progress, let diameter):
        LorvexTaskRing(progress: progress, isDone: isCompleting, diameter: diameter)
          .contentShape(Circle())
      }
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled || isCompleting)
    .accessibilityLabel(LorvexWatchCalmCopy.complete(title))
  }

  private func trigger() {
    guard isEnabled, !isCompleting else { return }
    lorvexAnimated(.spring(response: 0.34, dampingFraction: 0.6)) {
      isCompleting = true
    }
    Task {
      try? await Task.sleep(for: .milliseconds(300))
      let succeeded = await complete()
      #if os(watchOS)
        WKInterfaceDevice.current().play(succeeded ? .success : .failure)
      #endif
      isCompleting = false
    }
  }
}
