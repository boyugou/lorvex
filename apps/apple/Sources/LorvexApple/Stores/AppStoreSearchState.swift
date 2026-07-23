import Foundation

extension AppStore {
  var hasActiveSearch: Bool {
    !trimmedSearchText.isEmpty
  }

  var trimmedSearchText: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
