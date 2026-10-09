import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// The press that lifts a calendar event block for rescheduling, and the
/// travel of the finger after it, as a UIKit long-press recognizer.
///
/// The recognizer stays undecided until the finger has rested on the block for
/// ``minimumPressDuration``, and it fails if the finger travels further than
/// ``allowableMovement`` first. A swipe that starts on a block therefore stays
/// with the day pager (sideways) or the time grid's scroll view (up and down),
/// and only a finger that rests latches the block. A SwiftUI drag gesture
/// cannot make this split: one that is able to begin on a view takes every
/// touch that lands on it, so a swipe across the block would not reach the
/// pager.
///
/// A view that carries a lift must not also carry a context menu with items.
/// The system's context menu interaction holds back the other recognizers on
/// its view until the menu has appeared or failed, so the press would never
/// begin. A `.contextMenu` whose content is empty attaches no interaction.
///
/// Travel is measured from where the finger touched down, in window
/// coordinates. The block follows the finger, so a space local to the block
/// would shift under it.
struct MobileCalendarEventLift {
  /// How long the finger rests on the block before it lifts.
  static let minimumPressDuration: TimeInterval = 0.30
  /// How far, in points, the finger may travel before that and still latch.
  static let allowableMovement: CGFloat = 10

  /// Whether the block can be lifted. A disabled lift ignores every touch.
  let isEnabled: Bool
  /// The press latched, or the finger moved after it: the block follows the
  /// finger, which is now this far from where it touched down.
  let onMove: (CGSize) -> Void
  /// The finger lifted this far from where it touched down.
  let onDrop: (CGSize) -> Void
  /// The system took the touch away: the block stays where it was.
  let onCancel: () -> Void
}

extension View {
  /// Lifts the view under a finger that rests on it and reports the finger's
  /// travel (``MobileCalendarEventLift``). A no-op in the macOS SwiftPM build
  /// of this module, so call sites need no `#if os(iOS)`.
  func lorvexEventLift(_ lift: MobileCalendarEventLift) -> some View {
    #if os(iOS)
      gesture(lift)
    #else
      self
    #endif
  }
}

#if os(iOS)
  extension MobileCalendarEventLift: UIGestureRecognizerRepresentable {
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      /// Where the first finger touched down, in window coordinates.
      var origin = CGPoint.zero

      func gestureRecognizer(
        _ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch
      ) -> Bool {
        if recognizer.numberOfTouches == 0 { origin = touch.location(in: nil) }
        return true
      }

      /// A scroll view's pan or swipe waits for the press to decide: it begins
      /// as soon as the press fails, so a swipe loses no distance, and it never
      /// begins once the press has latched, so a lifted block is not carried
      /// off by the grid or the pager.
      func gestureRecognizer(
        _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
      ) -> Bool {
        Self.isScroll(other)
      }

      /// Every other recognizer runs beside the press. SwiftUI delivers the
      /// press's action through its own recognizer on the hosting view, which
      /// must stay alive for the press to be reported.
      func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
      ) -> Bool {
        !Self.isScroll(other)
      }

      private static func isScroll(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer is UIPanGestureRecognizer || recognizer is UISwipeGestureRecognizer
      }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
      let recognizer = UILongPressGestureRecognizer()
      recognizer.minimumPressDuration = Self.minimumPressDuration
      recognizer.allowableMovement = Self.allowableMovement
      recognizer.isEnabled = isEnabled
      recognizer.delegate = context.coordinator
      return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
      recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
      _ recognizer: UILongPressGestureRecognizer, context: Context
    ) {
      let finger = recognizer.location(in: nil)
      let origin = context.coordinator.origin
      let travel = CGSize(width: finger.x - origin.x, height: finger.y - origin.y)
      switch recognizer.state {
      case .began, .changed:
        onMove(travel)
      case .ended:
        onDrop(travel)
      case .cancelled:
        onCancel()
      default:
        break
      }
    }
  }
#endif
