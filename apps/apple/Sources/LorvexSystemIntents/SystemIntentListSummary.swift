import Foundation

/// The names a Siri or Shortcuts dialog lists: the first `shown` of them, then
/// how many more the result holds, joined as one list in the user's language
/// ("A, B, C, D, E, and 3 more"; "A、B、C、D、E和另外 3 个"). The count of the
/// rest is the list's last item, so the language's conjunction comes once,
/// before it, and the separators are the language's own.
enum SystemIntentListSummary {
  /// How many names a dialog reads out before it sums up the rest.
  static let shownCount = 5

  /// - Parameters:
  ///   - names: The names in the order the dialog reads them.
  ///   - total: How many results there are, which may exceed `names.count`
  ///     when the query fetched only a page of them.
  ///   - shown: How many names to read out before summing up the rest.
  static func names(_ names: [String], total: Int, shown: Int = shownCount) -> String {
    var items = Array(names.prefix(shown))
    let remaining = total - items.count
    if remaining > 0 {
      items.append(
        String(
          localized: "system.list.more", defaultValue: "\(remaining) more",
          table: "Localizable", bundle: SystemL10n.bundle))
    }
    return items.formatted(.list(type: .and))
  }
}
