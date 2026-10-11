import SwiftUI

/// A one-place move of a row in a manually ordered catalog (the lists or the
/// habits).
enum MobileReorderDirection {
  case up
  case down

  fileprivate var offset: Int { self == .up ? -1 : 1 }

  /// `order` with `id` swapped with its neighbour in this direction, or nil
  /// when `id` is not in `order` or already sits at that end.
  static func moved<ID: Equatable>(_ id: ID, in order: [ID], _ direction: Self) -> [ID]? {
    guard let index = order.firstIndex(of: id) else { return nil }
    let target = index + direction.offset
    guard order.indices.contains(target) else { return nil }
    var moved = order
    moved.swapAt(index, target)
    return moved
  }
}

enum MobileReorderCopy {
  static var moveUp: String {
    String(localized: "reorder.move_up", defaultValue: "Move Up", table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var moveDown: String {
    String(localized: "reorder.move_down", defaultValue: "Move Down", table: "Localizable", bundle: MobileL10n.bundle)
  }
}

/// "Move Up" and "Move Down" for a row's context menu. The row at an end of
/// the order keeps the item that cannot apply, dimmed, so the pair does not
/// change shape from row to row.
struct MobileReorderMenuItems: View {
  let canMoveUp: Bool
  let canMoveDown: Bool
  let moveUp: () -> Void
  let moveDown: () -> Void

  var body: some View {
    Button(action: moveUp) {
      Label(MobileReorderCopy.moveUp, systemImage: "chevron.up")
    }
    .disabled(!canMoveUp)
    Button(action: moveDown) {
      Label(MobileReorderCopy.moveDown, systemImage: "chevron.down")
    }
    .disabled(!canMoveDown)
  }
}

extension View {
  /// Gives a row of an ordered catalog the same two moves as VoiceOver
  /// actions, since a context menu is not offered to VoiceOver; only a move
  /// that applies is listed.
  func mobileReorderActions(
    canMoveUp: Bool, canMoveDown: Bool, moveUp: @escaping () -> Void,
    moveDown: @escaping () -> Void
  ) -> some View {
    accessibilityActions {
      if canMoveUp {
        Button(MobileReorderCopy.moveUp, action: moveUp)
      }
      if canMoveDown {
        Button(MobileReorderCopy.moveDown, action: moveDown)
      }
    }
  }
}
