import AppIntents

struct UpdateLorvexTaskIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.update.title", defaultValue: "Update Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.update.description", defaultValue: "Update Lorvex task details from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.title", defaultValue: "Title", table: "Localizable", bundle: SystemL10n.bundle))
  var title: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.notes", defaultValue: "Notes", table: "Localizable", bundle: SystemL10n.bundle))
  var notes: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.priority", defaultValue: "Priority", table: "Localizable", bundle: SystemL10n.bundle))
  var priority: LorvexPriorityOption?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.estimated_minutes", defaultValue: "Estimated Minutes", table: "Localizable", bundle: SystemL10n.bundle),
    inclusiveRange: (1, 1_440))
  var estimatedMinutes: Int?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.planned_date", defaultValue: "Planned Date", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var plannedDate: Date?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.remove_planned_date", defaultValue: "Remove Planned Date", table: "Localizable", bundle: SystemL10n.bundle),
    default: false)
  var removesPlannedDate: Bool

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.tags", defaultValue: "Tags", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.tags_description", defaultValue: "Comma, space, or newline separated tags.", table: "Localizable", bundle: SystemL10n.bundle))
  var tags: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.depends_on", defaultValue: "Depends On", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.batch.parameter.task_ids_description", defaultValue: "Comma, space, or newline separated task IDs.", table: "Localizable", bundle: SystemL10n.bundle))
  var dependsOn: String?

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
  }

  init(
    task: LorvexTaskEntity,
    title: String? = nil,
    notes: String? = nil,
    priority: LorvexPriorityOption? = nil,
    estimatedMinutes: Int? = nil,
    plannedDate: Date? = nil,
    removesPlannedDate: Bool = false,
    tags: String? = nil,
    dependsOn: String? = nil
  ) {
    self.task = task
    self.title = title
    self.notes = notes
    self.priority = priority
    self.estimatedMinutes = estimatedMinutes
    self.plannedDate = plannedDate
    self.removesPlannedDate = removesPlannedDate
    self.tags = tags
    self.dependsOn = dependsOn
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.updateTask(
      id: task.id,
      title: title,
      notes: notes,
      priority: priority?.level,
      estimatedMinutes: estimatedMinutes,
      // An empty planned date is the runner's "clear the day".
      plannedDate: removesPlannedDate ? "" : plannedDate.map(IntentDateText.day),
      tagsText: tags,
      dependsOnText: dependsOn
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.update.dialog", defaultValue: "Updated \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
