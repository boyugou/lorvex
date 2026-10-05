import Foundation
import LorvexDomain

extension String {
  /// Whether `term` occurs in this text the way Lorvex search compares text on
  /// every surface that filters already-loaded values (palette, pickers,
  /// Siri entity queries, list/habit/memory search).
  ///
  /// A term matches when `localizedStandardContains` finds it (the user's
  /// language decides case, accent, and width handling) or when its folded
  /// form (``SearchFold/fold(_:)``) occurs in the folded text. The second rule
  /// covers what the system comparison leaves apart: "lodz" in "Łódź", "di
  /// cho" in "Đi chợ", "isik" in "Işık", "orsted" in "Ørsted", "اسماء" in
  /// "أسماء", and a query typed in full-width letters ("ｔｏｄａｙ") against
  /// plain text. An empty term matches nothing.
  public func containsSearchTerm(_ term: String) -> Bool {
    guard !term.isEmpty else { return false }
    if localizedStandardContains(term) { return true }
    let needle = SearchFold.fold(term)
    return !needle.isEmpty && SearchFold.fold(self).contains(needle)
  }
}
