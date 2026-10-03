import CoreGraphics
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

// The columns a row uses share its width, each at most the maximum: four
// habits fill a phone's row and spread across a wide iPad card when the
// maximum is unbounded, and keep to the leading edge, 96 pt wide, when it is
// not. Three habits, or five in rows of three and two, share the phone's row
// in thirds.
@Test(arguments: [
  (itemCount: 4, width: CGFloat(350), maximum: CGFloat.infinity, columns: 4, columnWidth: CGFloat(81.5)),
  (itemCount: 4, width: CGFloat(830), maximum: CGFloat.infinity, columns: 4, columnWidth: CGFloat(201.5)),
  (itemCount: 4, width: CGFloat(830), maximum: CGFloat(96), columns: 4, columnWidth: CGFloat(96)),
  (itemCount: 3, width: CGFloat(350), maximum: CGFloat.infinity, columns: 3, columnWidth: CGFloat(334) / 3),
  (itemCount: 5, width: CGFloat(350), maximum: CGFloat.infinity, columns: 3, columnWidth: CGFloat(334) / 3),
])
func balancedGridColumnsShareTheWidth(
  itemCount: Int, width: CGFloat, maximum: CGFloat, columns: Int, columnWidth: CGFloat
) {
  let layout = LorvexBalancedGrid.columns(
    itemCount: itemCount, width: width, minimumColumnWidth: 76, maximumColumnWidth: maximum, columnSpacing: 8)
  #expect(layout.count == columns)
  #expect(abs(layout.width - columnWidth) < 0.001)
}
