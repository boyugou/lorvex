import LorvexCore

/// Copy shared by the memory delete confirmations: the catalog rows, the
/// detail page, and the batch bar.
enum MobileMemoryDeleteCopy {
  /// The question for deleting one entry, naming it.
  static func title(for entry: MemoryEntry) -> String {
    String(
      format: String(
        localized: "memory.delete.confirm.title", defaultValue: "Delete memory “%@”?",
        table: "Localizable", bundle: MobileL10n.bundle),
      entry.displayTitle)
  }

  /// The question for deleting the selected entries.
  static var batchTitle: String {
    String(
      localized: "memory.batch.delete_confirm.title", defaultValue: "Delete selected memory?",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// What a deletion means, under either question.
  static var message: String {
    String(
      localized: "memory.delete.confirm.message",
      defaultValue: "The memory entry is removed. This can’t be undone.", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
