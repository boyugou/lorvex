import Testing

@testable import LorvexApple

// `mergeReorderedVisible` splices a reordered subset of visible IDs back into
// the full saved order so reordering a search-filtered list doesn't drop the
// hidden items' positions.

@MainActor
@Test
func mergeReorderedVisibleWithNoFilterIsTheReorderedSequence() {
  // Every item is visible → result is exactly the reordered sequence.
  let result = AppStore.mergeReorderedVisible(
    ["b", "a", "c"], intoFullOrder: ["a", "b", "c"])
  #expect(result == ["b", "a", "c"])
}

@MainActor
@Test
func mergeReorderedVisibleKeepsHiddenItemsInPlace() {
  // Full order a,b,c,d; only a and c are visible and got reordered to c,a.
  // b and d (search-hidden) keep their slots; a/c reorder within their slots.
  let result = AppStore.mergeReorderedVisible(
    ["c", "a"], intoFullOrder: ["a", "b", "c", "d"])
  #expect(result == ["c", "b", "a", "d"])
}

@MainActor
@Test
func mergeReorderedVisibleWithEmptySubsetLeavesOrderUntouched() {
  let result = AppStore.mergeReorderedVisible(
    [], intoFullOrder: ["a", "b", "c"])
  #expect(result == ["a", "b", "c"])
}
