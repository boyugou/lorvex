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

  /// Applies an `IndexSet` move on the currently-visible habits, merged back into
  /// the full catalog order so habits hidden by an active search keep their
  /// positions, then persists the resulting order via the synced core.
  func moveHabits(fromOffsets source: IndexSet, toOffset destination: Int) async {
    var visible = filteredHabits
    visible.move(fromOffsets: source, toOffset: destination)
    let merged = Self.mergeReorderedVisible(
      visible.map(\.id), intoFullOrder: (habits?.habits ?? []).map(\.id))
    await reorderHabits(merged)
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
