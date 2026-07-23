import LorvexCore

extension TaskAccessibilityVocabulary {
  /// The macOS app's localized VoiceOver vocabulary, resolved from the
  /// LorvexApple string catalog. Status words reuse the already-localized
  /// `TaskDisplayText.status`. Placeholders (`%@` priority/due, `%lld` minutes)
  /// are preserved across translations and enforced by the catalog verifier.
  static var lorvexLocalized: TaskAccessibilityVocabulary {
    TaskAccessibilityVocabulary(
      focusedTask: String(localized: "a11y.task.focused", defaultValue: "Focused task", table: "Localizable", bundle: LorvexL10n.bundle),
      priorityTaskFormat: String(localized: "a11y.task.priority_format", defaultValue: "%@ task", table: "Localizable", bundle: LorvexL10n.bundle),
      minutesFormat: String(localized: "a11y.task.minutes_format", defaultValue: "%lld minutes", table: "Localizable", bundle: LorvexL10n.bundle),
      dueFormat: String(localized: "a11y.task.due_format", defaultValue: "due %@", table: "Localizable", bundle: LorvexL10n.bundle),
      overdueFormat: String(localized: "a11y.task.overdue_format", defaultValue: "overdue %@", table: "Localizable", bundle: LorvexL10n.bundle),
      statusName: { TaskDisplayText.status($0) }
    )
  }
}
