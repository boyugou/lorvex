import Foundation
import GRDB
import LorvexDomain

extension LorvexStore {
  /// Name of the SQL scalar function that returns ``SearchFold/fold(_:)`` of
  /// its text argument (`NULL` stays `NULL`). Queries may call it; no schema
  /// object may, because another process opening the same database file with
  /// an older build does not register it.
  static let searchFoldFunctionName = "lorvex_fold"

  /// Registers the search-fold SQL function on every connection the
  /// configuration opens.
  static func registerSearchFunctions(in config: inout Configuration) {
    config.prepareDatabase { db in
      db.add(
        function: DatabaseFunction(searchFoldFunctionName, argumentCount: 1, pure: true) { values in
          guard let text = String.fromDatabaseValue(values[0]) else { return nil }
          return SearchFold.fold(text)
        })
    }
  }
}
