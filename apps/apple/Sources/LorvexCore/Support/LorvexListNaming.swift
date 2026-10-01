import Foundation

/// How a list's stored name becomes the name the interface shows.
///
/// Every list shows its stored name except the seeded Inbox. The schema seeds
/// that list (id `inbox`) with the English name "Inbox", and the name is
/// ordinary synced data that MCP clients read and may change. While the stored
/// name is still the seeded one, the interface shows the Inbox under its word
/// in the interface language ("收件箱" in Simplified Chinese); once a person or
/// an assistant renames the list, every surface shows the chosen name. Showing
/// a list never changes its stored name.
public enum LorvexListNaming {
  /// The seeded Inbox's list id.
  public static let inboxID = "inbox"
  /// The name the schema seeds the Inbox with.
  public static let seededInboxName = "Inbox"

  /// The Inbox's name in the interface language.
  public static var localizedInboxName: String {
    String(
      localized: "list.inbox.name", defaultValue: "Inbox", table: "Localizable",
      bundle: CoreL10n.bundle)
  }

  /// Whether `id` and `name` describe the Inbox under its seeded name.
  public static func isSeededInbox(id: String, name: String) -> Bool {
    id == inboxID && name == seededInboxName
  }

  /// The name to show for a list: `inboxName` for the seeded Inbox, the stored
  /// `name` for every other list.
  public static func displayName(
    id: String, name: String, inboxName: String = LorvexListNaming.localizedInboxName
  ) -> String {
    isSeededInbox(id: id, name: name) ? inboxName : name
  }

  /// The names a search or a typed `#list` may use for a list: the shown name,
  /// then the stored name when it differs, so both "收件箱" and "Inbox" find
  /// the seeded Inbox in a Chinese interface.
  public static func matchNames(
    id: String, name: String, inboxName: String = LorvexListNaming.localizedInboxName
  ) -> [String] {
    let shown = displayName(id: id, name: name, inboxName: inboxName)
    return shown == name ? [name] : [shown, name]
  }

  /// The name to store when an editor that started from the shown name saves
  /// `editedName`. Saving the seeded Inbox with its shown name unchanged keeps
  /// the seeded name, so the interface-language word never becomes stored,
  /// synced data just because the editor displayed it; any other edit is
  /// stored as typed.
  public static func nameToStore(
    id: String, storedName: String, editedName: String,
    inboxName: String = LorvexListNaming.localizedInboxName
  ) -> String {
    isSeededInbox(id: id, name: storedName) && editedName == inboxName ? storedName : editedName
  }
}

extension LorvexList {
  /// The list's name as the interface shows it: the seeded Inbox in the
  /// interface language until someone renames it, every other list under its
  /// stored `name` (``LorvexListNaming``).
  public var displayName: String {
    LorvexListNaming.displayName(id: id, name: name)
  }

  /// The names a search or a typed `#list` may use for this list
  /// (``LorvexListNaming/matchNames(id:name:inboxName:)``).
  public var matchNames: [String] {
    LorvexListNaming.matchNames(id: id, name: name)
  }
}
