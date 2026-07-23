import MCP

enum HabitToolDefinitions {
  static let all: [ToolDefinition] = [
    .read(32, ListHabitToolCatalog.getHabitsTool) {
      try await $0.habitsResult(arguments: $1)
    },
    .read(33, ListHabitToolCatalog.getHabitCompletionsTool) {
      try await $0.habitCompletionsResult(arguments: $1)
    },
    .read(34, ListHabitToolCatalog.getHabitStatsTool) {
      try await $0.habitStatsResult(arguments: $1)
    },
    .read(35, ListHabitToolCatalog.getHabitReminderPoliciesTool) {
      try await $0.getHabitReminderPoliciesResult(arguments: $1)
    },
    .write(36, ListHabitToolCatalog.upsertHabitReminderPolicyTool) {
      try await $0.upsertHabitReminderPolicyResult(arguments: $1)
    },
    .write(37, ListHabitToolCatalog.deleteHabitReminderPolicyTool) {
      try await $0.deleteHabitReminderPolicyResult(arguments: $1)
    },
    .write(65, ListHabitToolCatalog.createHabitTool) {
      try await $0.createHabitResult(arguments: $1)
    },
    .write(66, ListHabitToolCatalog.updateHabitTool) {
      try await $0.updateHabitResult(arguments: $1)
    },
    .write(67, ListHabitToolCatalog.deleteHabitTool) {
      try await $0.deleteHabitResult(arguments: $1)
    },
    .write(68, ListHabitToolCatalog.reorderHabitsTool) {
      try await $0.reorderHabitsResult(arguments: $1)
    },
    .write(92, ListHabitToolCatalog.completeHabitTool) {
      try await $0.completeHabitResult(arguments: $1)
    },
    .write(93, ListHabitToolCatalog.batchCompleteHabitTool) {
      try await $0.batchCompleteHabitResult(arguments: $1)
    },
    .write(94, ListHabitToolCatalog.uncompleteHabitTool) {
      try await $0.uncompleteHabitResult(arguments: $1)
    },
    .write(95, ListHabitToolCatalog.adjustHabitCompletionTool) {
      try await $0.adjustHabitCompletionResult(arguments: $1)
    },
  ]
}
