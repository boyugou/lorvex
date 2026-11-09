import Foundation
import LorvexCore

// MARK: - Reorder actions

/// Reorder actions for habits and lists.
///
/// Both persist their manual order through a synced core `position`
/// column (``reorderHabits(_:)`` / ``reorderLists(_:)``), so a drag converges
/// across devices like any other edit — there is no local `UserDefaults` order
/// for either of them.
extension AppStore {
  // MARK: - Habit reorder

  /// Persist a full habit order through the synced core and refresh the catalog
  /// from the returned snapshot (already in `position` order).
  func reorderHabits(_ orderedIDs: [LorvexHabit.ID]) async {
    await perform {
      habits = try await core.reorderHabits(
        orderedIDs: orderedIDs, date: logicalTodayDateString)
    }
  }

  /// Moves `habitID` to just before, or with `after` just after, `neighborID`
  /// in the catalog order as it stands when the move runs, then persists that
  /// order via the synced core. Positions read when the user clicked can be
  /// out of date by then (a sync or an assistant changed the catalog), and an
  /// offset past the end of the order traps, so the move works from ids. A
  /// habit that is gone by then is left alone.
  func moveHabit(_ habitID: LorvexHabit.ID, beside neighborID: LorvexHabit.ID, after: Bool) async {
    var ordered = orderedHabits.map(\.id)
    guard habitID != neighborID, let from = ordered.firstIndex(of: habitID) else { return }
    ordered.remove(at: from)
    guard let neighbor = ordered.firstIndex(of: neighborID) else { return }
    ordered.insert(habitID, at: after ? neighbor + 1 : neighbor)
    await reorderHabits(ordered)
  }

  // MARK: - List reorder

  /// Persist a full list order through the synced core and refresh the catalog
  /// from the returned snapshot (already in `position` order).
  func reorderLists(_ orderedIDs: [LorvexList.ID]) async {
    await perform {
      lists = try await core.reorderLists(orderedIDs: orderedIDs)
    }
  }

  /// Splices a reordered subset of currently-visible IDs back into `fullOrder`,
  /// leaving IDs absent from the subset (hidden by a search filter) at their
  /// existing positions. With no active filter the visible subset is the whole
  /// list, so this is an identity over the reordered sequence.
  static func mergeReorderedVisible(
    _ reorderedVisible: [String], intoFullOrder fullOrder: [String]
  ) -> [String] {
    let visible = Set(reorderedVisible)
    var iterator = reorderedVisible.makeIterator()
    var result: [String] = []
    result.reserveCapacity(fullOrder.count)
    for id in fullOrder {
      if visible.contains(id) {
        if let next = iterator.next() { result.append(next) }
      } else {
        result.append(id)
      }
    }
    return result
  }
}
