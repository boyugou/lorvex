import Foundation
import LorvexCore

extension AppStore {
  /// The most characters of a list's name the toolbar search prompt carries:
  /// the search field is a narrow toolbar item.
  nonisolated static let searchPromptListNameLimit = 24

  /// The most characters of a list's name the quick-add placeholder carries:
  /// the field spans its workspace, but a list opened in a window of its own
  /// can be narrow.
  nonisolated static let quickAddPromptListNameLimit = 40

  /// A list's name as a field's prompt carries it: a name past `limit`
  /// characters is cut and ends with an ellipsis, because a text field clips a
  /// placeholder wider than itself mid-word with no mark that it continues. The
  /// cut falls between words when a space lies in the second half of the
  /// kept text, and inside a word otherwise.
  nonisolated static func promptListName(_ name: String, limit: Int) -> String {
    guard name.count > limit else { return name }
    let head = name.prefix(limit)
    var kept = String(head)
    if name[head.endIndex] != " ", let space = kept.lastIndex(of: " "),
      kept.distance(from: kept.startIndex, to: space) >= limit / 2
    {
      kept = String(kept[..<space])
    }
    return kept.trimmingCharacters(in: .whitespaces) + "…"
  }

  /// The placeholder of the quick-add field inside the list named `listName`.
  nonisolated static func quickAddPlaceholder(listName: String) -> String {
    String(
      format: String(
        localized: "list_detail.quick_add.placeholder",
        defaultValue: "Add a task to “%@”",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      promptListName(listName, limit: quickAddPromptListNameLimit))
  }
}
