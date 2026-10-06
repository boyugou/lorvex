import LorvexCore
import SwiftUI

/// Makes a view a drop target for dragged tasks: it is outlined and tinted while
/// a drag is over it, and a drop hands the ids of every dragged task to `drop`.
/// Only task drags qualify (`LorvexTaskRef`); text or files dragged in from
/// other apps are not accepted.
///
/// `key` names this target among its siblings and `targetedKey` is the one
/// state they share (the sidebar rows, the list cards), so exactly one of them
/// is highlighted at a time.
struct TaskDropTarget<Key: Hashable>: ViewModifier {
  let key: Key
  @Binding var targetedKey: Key?
  /// How far the highlight extends beyond the target's own frame. A sidebar row
  /// passes the gap between its content and the system's selection capsule, so
  /// the outline lies where the selection highlight would.
  let outset: EdgeInsets
  let cornerRadius: CGFloat
  let drop: ([LorvexTask.ID]) -> Void

  private var isTargeted: Bool { targetedKey == key }

  func body(content: Content) -> some View {
    content
      .background {
        if isTargeted {
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.tint.opacity(0.16))
            .overlay {
              RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.tint, lineWidth: 1.5)
            }
            .padding(EdgeInsets(
              top: -outset.top, leading: -outset.leading,
              bottom: -outset.bottom, trailing: -outset.trailing))
        }
      }
      .reduceMotionAnimation(.snappy(duration: 0.12), value: isTargeted)
      .dropDestination(for: LorvexTaskRef.self) { refs, _ in
        let ids = refs.droppedTaskIDs
        guard !ids.isEmpty else { return false }
        drop(ids)
        return true
      } isTargeted: { targeted in
        if targeted {
          targetedKey = key
        } else if targetedKey == key {
          targetedKey = nil
        }
      }
  }
}

extension View {
  /// See ``TaskDropTarget``.
  func taskDropTarget<Key: Hashable>(
    _ key: Key, targeted: Binding<Key?>, outset: EdgeInsets = EdgeInsets(),
    cornerRadius: CGFloat = LorvexDesign.Radius.s, drop: @escaping ([LorvexTask.ID]) -> Void
  ) -> some View {
    modifier(
      TaskDropTarget(
        key: key, targetedKey: targeted, outset: outset, cornerRadius: cornerRadius, drop: drop))
  }
}
