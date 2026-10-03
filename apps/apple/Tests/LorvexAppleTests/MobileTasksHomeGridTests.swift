import CoreGraphics
import Testing

@testable import LorvexMobile

// The Tasks home's four cards stand in one row where four fit at the minimum
// card width, and in two rows of two where they do not, even where three
// would fit: an upright phone's 370 points hold two, a phone on its side
// (718) and an iPad's readable column (758) hold four. Before the width is
// measured the grid lays out as on the phone.
@Test(arguments: [
  (width: CGFloat(370), columns: 2),
  (width: CGFloat(520), columns: 2),
  (width: CGFloat(718), columns: 4),
  (width: CGFloat(758), columns: 4),
  (width: CGFloat(140), columns: 1),
  (width: CGFloat(0), columns: 2),
])
func tasksHomeGridFillsItsRowsEvenly(width: CGFloat, columns: Int) {
  #expect(MobileStoreTasksHomeView.smartGridColumnCount(width: width, itemCount: 4) == columns)
}
