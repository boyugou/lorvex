import MCP

/// The day-planning tools: the day's briefing and its times. Which tasks a day
/// holds is set through the task tools (`planned_date`, deferral), not here.
enum DayPlanningToolDefinitions {
  static let all: [ToolDefinition] = [
    .write(84, DayPlanningToolCatalog.setDailyBriefingTool) {
      try await $0.setDailyBriefingResult(arguments: $1)
    },
    .read(85, DayPlanningToolCatalog.proposeDailyScheduleTool) {
      try await $0.proposeDailyScheduleResult(arguments: $1)
    },
    .write(86, DayPlanningToolCatalog.saveDailyScheduleTool) {
      try await $0.saveDailyScheduleResult(arguments: $1)
    },
    .read(87, DayPlanningToolCatalog.getDailyScheduleTool) {
      try await $0.getDailyScheduleResult(arguments: $1)
    },
  ]
}
