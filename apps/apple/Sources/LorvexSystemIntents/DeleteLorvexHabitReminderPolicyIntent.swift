import AppIntents

struct DeleteLorvexHabitReminderPolicyIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reminder_policy.delete.title", defaultValue: "Delete Lorvex Habit Reminder Policy", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reminder_policy.delete.description", defaultValue: "Delete a Lorvex habit reminder policy by ID.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.policy_id", defaultValue: "Policy ID", table: "Localizable", bundle: SystemL10n.bundle))
  var policyID: String

  init() {
    policyID = ""
  }

  init(policyID: String) {
    self.policyID = policyID
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.delete", defaultValue: "Delete this item? This can't be undone.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let removed = try await LorvexTaskIntentRunner.deleteHabitReminderPolicy(policyID: policyID)
    guard let removed else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.habit.reminder_policy.delete.not_found_dialog",
            defaultValue: "No habit reminder policy with that ID.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.reminder_policy.delete.dialog",
          defaultValue: "Deleted the \(removed.habitName) reminder at \(removed.reminderTime).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
