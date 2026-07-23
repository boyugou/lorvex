import Foundation
import Testing

@testable import LorvexApple

// The Tasks table's List column shows the list *name* but sorts on `listID`.
// `ListNameComparator` must order by the resolved name so the visible order
// matches the click, with unlisted / unresolved tasks last.

private let names = ["z-id": "Apple", "a-id": "Zebra"]

@Test
func listNameComparatorOrdersByResolvedNameNotID() {
  let cmp = ListNameComparator(order: .forward, namesByID: names)
  // "z-id" → "Apple", "a-id" → "Zebra": Apple sorts before Zebra even though
  // the ids would sort the other way.
  #expect(cmp.compare("z-id", "a-id") == .orderedAscending)
  #expect(cmp.compare("a-id", "z-id") == .orderedDescending)
}

@Test
func listNameComparatorSortsMissingAndUnresolvedLast() {
  let cmp = ListNameComparator(order: .forward, namesByID: names)
  #expect(cmp.compare(nil, "z-id") == .orderedDescending)
  #expect(cmp.compare("z-id", nil) == .orderedAscending)
  // An id with no name entry is treated as unlisted (sorts last).
  #expect(cmp.compare("unknown", "z-id") == .orderedDescending)
  #expect(cmp.compare(nil, nil) == .orderedSame)
}

@Test
func listNameComparatorReverseFlipsNamesButKeepsTieAndMissing() {
  let cmp = ListNameComparator(order: .reverse, namesByID: names)
  #expect(cmp.compare("z-id", "a-id") == .orderedDescending)
  // Missing values flip with order too (matches the date/string column policy).
  #expect(cmp.compare(nil, "z-id") == .orderedAscending)
  #expect(cmp.compare(nil, nil) == .orderedSame)
}
