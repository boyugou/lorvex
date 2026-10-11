import Foundation
import LorvexCore

/// A change just made that the Undo banner offers to take back: completing,
/// cancelling, or filing tasks into another list. One change is on offer at a
/// time; a newer change replaces it.
struct MobileUndoOffer: Equatable, Identifiable {
  /// A fresh id per offer, so the banner restarts its timeout for a change that
  /// reads the same as the last.
  let id = UUID()
  let message: String
}

/// The words the Undo banner shows for each kind of change.
enum MobileUndoCopy {
  static var completed: String {
    String(
      localized: "undo.banner.completed", defaultValue: "Completed", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var cancelled: String {
    String(
      localized: "undo.banner.cancelled", defaultValue: "Cancelled", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var undo: String {
    String(
      localized: "undo.action", defaultValue: "Undo", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// "Moved 3 tasks to Reading.", pluralized through the catalog.
  static func moved(count: Int, listName: String) -> String {
    String(
      localized: "task.move.toast", defaultValue: "Moved \(count) tasks to \(listName).",
      table: "Localizable", bundle: MobileL10n.bundle)
  }
}

extension MobileStore {
  /// Puts `message` on the Undo banner with `undo` as what its button runs,
  /// replacing any change already on offer.
  func offerUndo(_ message: String, undo: @escaping @MainActor () async -> Void) {
    undoOfferAction = undo
    lorvexAnimated(.snappy(duration: 0.25)) {
      undoOffer = MobileUndoOffer(message: message)
    }
  }

  /// Offers to reopen `ids`. A reopen is the exact reverse of a completion or a
  /// cancellation: the core also cancels the next occurrence a repeating task's
  /// completion generated, so no duplicate is left behind.
  func offerReopenUndo(ids: [LorvexTask.ID], message: String) {
    guard !ids.isEmpty else { return }
    offerUndo(message) { [weak self] in await self?.reopenTasks(ids) }
  }

  /// Offers to file the `movedCount` tasks just moved into `listID` back into
  /// the lists they came from (`back`, one step per list).
  func offerListMoveUndo(back: [TaskListMoveStep], movedCount: Int, toListID listID: LorvexList.ID) {
    let listName =
      lists?.lists.first { $0.id == listID }?.displayName ?? LorvexListNaming.localizedInboxName
    offerUndo(MobileUndoCopy.moved(count: movedCount, listName: listName)) { [weak self] in
      for step in back { await self?.fileTasks(step.ids, toListID: step.listID) }
    }
  }

  /// Runs the offered undo and takes the banner down. The offer clears first,
  /// so a second tap on the banner while the undo runs does nothing.
  func performUndoOffer() async {
    guard let action = undoOfferAction else { return }
    dismissUndoOffer()
    await action()
  }

  /// Takes the banner down without undoing anything.
  func dismissUndoOffer() {
    undoOfferAction = nil
    guard undoOffer != nil else { return }
    lorvexAnimated(.snappy(duration: 0.2)) { undoOffer = nil }
  }
}
