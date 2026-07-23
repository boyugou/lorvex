import LorvexCore

extension TaskAccessibilityVocabulary {
  /// The iOS/iPadOS/visionOS localized VoiceOver vocabulary, resolved from the
  /// LorvexMobile string catalog. Status words reuse the already-localized
  /// `MobileTaskDisplayText.status`. Placeholders (`%@` priority/due) and the
  /// native pluralized minutes interpolation are enforced by the verifier.
  static var mobileLocalized: TaskAccessibilityVocabulary {
    TaskAccessibilityVocabulary(
      focusedTask: String(
        localized: "a11y.task.focused", defaultValue: "Focused task", table: "Localizable",
        bundle: MobileL10n.bundle),
      priorityTaskFormat: String(
        localized: "a11y.task.priority_format", defaultValue: "%@ task", table: "Localizable",
        bundle: MobileL10n.bundle),
      minutesText: { minutes in
        String(
          localized: "a11y.task.minutes_format", defaultValue: "\(minutes) minutes",
          table: "Localizable", bundle: MobileL10n.bundle)
      },
      dueFormat: String(
        localized: "a11y.task.due_format", defaultValue: "due %@", table: "Localizable",
        bundle: MobileL10n.bundle),
      overdueFormat: String(
        localized: "a11y.task.overdue_format", defaultValue: "overdue %@", table: "Localizable",
        bundle: MobileL10n.bundle),
      statusName: { MobileTaskDisplayText.status($0) }
    )
  }
}
