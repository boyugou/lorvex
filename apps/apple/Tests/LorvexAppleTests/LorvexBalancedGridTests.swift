import LorvexCore
import Testing

// A balanced grid fills the fewest rows that hold its items, as evenly as they
// can be filled, so a row is never left with a lone item under full ones: four
// habits where three fit make two rows of two, five where four fit make a row
// of three over a row of two.
@Test(arguments: [
  (itemCount: 4, capacity: 3, columns: 2),
  (itemCount: 5, capacity: 4, columns: 3),
  (itemCount: 6, capacity: 4, columns: 3),
  (itemCount: 7, capacity: 4, columns: 4),
  (itemCount: 9, capacity: 4, columns: 3),
  (itemCount: 4, capacity: 4, columns: 4),
  (itemCount: 2, capacity: 4, columns: 2),
  (itemCount: 1, capacity: 4, columns: 1),
  (itemCount: 0, capacity: 4, columns: 1),
  (itemCount: 3, capacity: 0, columns: 1),
])
func balancedGridSpreadsItemsEvenlyOverItsRows(itemCount: Int, capacity: Int, columns: Int) {
  #expect(LorvexBalancedGrid.columnCount(itemCount: itemCount, capacity: capacity) == columns)
}
