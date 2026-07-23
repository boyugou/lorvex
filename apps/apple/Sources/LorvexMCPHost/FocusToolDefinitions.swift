import MCP

enum FocusToolDefinitions {
  static let all: [ToolDefinition] = [
    .write(84, FocusToolCatalog.setCurrentFocusTool) {
      try await $0.setCurrentFocusResult(arguments: $1)
    },
    .read(85, FocusToolCatalog.getCurrentFocusTool) {
      try await $0.getCurrentFocusResult(arguments: $1)
    },
    .write(86, FocusToolCatalog.addToCurrentFocusTool) {
      try await $0.addToCurrentFocusResult(arguments: $1)
    },
    .read(87, FocusToolCatalog.proposeDailyScheduleTool) {
      try await $0.proposeDailyScheduleResult(arguments: $1)
    },
    .write(88, FocusToolCatalog.saveFocusScheduleTool) {
      try await $0.saveFocusScheduleResult(arguments: $1)
    },
    .read(89, FocusToolCatalog.getSavedFocusScheduleTool) {
      try await $0.getSavedFocusScheduleResult(arguments: $1)
    },
    .write(90, FocusToolCatalog.removeFromCurrentFocusTool) {
      try await $0.removeFromCurrentFocusResult(arguments: $1)
    },
    .write(91, FocusToolCatalog.clearCurrentFocusTool) {
      try await $0.clearCurrentFocusResult(arguments: $1)
    },
  ]
}
