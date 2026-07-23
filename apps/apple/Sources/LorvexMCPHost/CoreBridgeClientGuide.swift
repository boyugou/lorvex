import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadGuide(topic: String?) async throws -> Value {
    let diagnostics = try await service.loadRuntimeDiagnostics()
    let guide = diagnostics.guide
    let setup = diagnostics.setup
    // Compute the live state instead of hardcoding zeros: memory depth,
    // configured preference keys, and whether today has a focus plan.
    let memory = try await service.loadMemory()
    let preferences = try await service.getAllPreferences()
    let logicalDay = try await service.getSessionContext().date
    let focus = try await service.loadCurrentFocus(date: logicalDay)
    let configuredPreferences = preferences.values.keys.sorted().map(Value.string)
    let hasCurrentFocus = focus.map { !$0.taskIDs.isEmpty } ?? false

    // Tailor the guidance to the requested topic, folding in live state, rather
    // than echoing the topic but returning the generic runtime summary.
    let resolvedTopic = Self.canonicalGuideTopic(topic)
    let copy = Self.guideCopy(
      topic: resolvedTopic,
      runtimeSummary: guide.summary,
      setupCompleted: setup.setupCompleted,
      taskCount: setup.taskCount,
      listCount: setup.listCount,
      hasCurrentFocus: hasCurrentFocus,
      memoryCount: memory.entries.count,
      configuredPreferenceCount: configuredPreferences.count)
    return .object([
      "topic": .string(resolvedTopic),
      "state": .object([
        "setup_completed": .bool(setup.setupCompleted),
        "task_count": .int(setup.taskCount),
        "list_count": .int(setup.listCount),
        "has_current_focus": .bool(hasCurrentFocus),
        "memory_count": .int(memory.entries.count),
        "configured_preferences": .array(configuredPreferences),
      ]),
      "guide": .object([
        // System-authored guidance copy. Keyed `guidance` (not `summary`) so the
        // central response fencer leaves it unfenced — `summary` is a
        // userContentKey (Core Design Rule 6: never fence system fields).
        "guidance": .string(copy.summary),
        "suggested_actions": .array(copy.actions.map(Value.string)),
      ]),
    ])
  }

  /// Documented guide topics. Anything unrecognized (or nil) resolves to
  /// `overview` so the response always carries a known topic.
  static func canonicalGuideTopic(_ topic: String?) -> String {
    let known: Set<String> = [
      "overview", "getting_started", "task_management", "current_focus",
      "lists", "focus_mode", "weekly_review", "preferences", "data_and_export",
    ]
    guard let topic = topic?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      known.contains(topic)
    else { return "overview" }
    return topic
  }

  /// Per-topic guidance copy. The summary and suggested actions are specific to
  /// the topic and fold in live counts/state so the assistant gets actionable,
  /// situation-aware guidance instead of a generic blurb.
  static func guideCopy(
    topic: String,
    runtimeSummary: String,
    setupCompleted: Bool,
    taskCount: Int,
    listCount: Int,
    hasCurrentFocus: Bool,
    memoryCount: Int,
    configuredPreferenceCount: Int
  ) -> (summary: String, actions: [String]) {
    switch topic {
    case "getting_started":
      if setupCompleted {
        return (
          "Setup is complete (\(listCount) list(s), \(taskCount) task(s)). Capture work into lists and let the assistant plan from there.",
          [
            "Capture tasks with create_task or batch_create_tasks.",
            "Organize with create_list and move_task_to_list.",
            "Plan the day with set_current_focus and propose_daily_schedule.",
          ])
      }
      return (
        "Setup isn't complete yet (\(listCount) list(s), \(taskCount) task(s)). Finish onboarding so defaults and working hours are in place.",
        [
          "Create at least one list with create_list.",
          "Capture a few tasks with create_task or batch_create_tasks.",
          "Call complete_setup with working_hours, timezone, and default_list_id.",
        ])
    case "task_management":
      return (
        "Tasks carry priority, planned_date, tags, dependencies, a checklist, reminders, and recurrence. Status transitions go through complete/cancel/reopen/defer and start/pause — never update_task. start_task marks work in_progress (an actionable state that surfaces wherever open does); pause_task clears it.",
        [
          "Capture with create_task / batch_create_tasks; enrich fields with update_task.",
          "Break work down with add_task_checklist_item; set deadlines with add_task_reminder.",
          "Change status with complete_task / cancel_task / reopen_task / defer_task; mark active work with start_task and clear it with pause_task.",
          "Surface load with get_upcoming_tasks, get_deferred_tasks, and search_tasks.",
        ])
    case "current_focus":
      if hasCurrentFocus {
        return (
          "Today already has a focus plan. Refine it or turn it into a time-blocked schedule.",
          [
            "Read the plan with get_current_focus.",
            "Adjust membership with add_to_current_focus / remove_from_current_focus.",
            "Time-block with propose_daily_schedule, then persist with save_focus_schedule.",
          ])
      }
      return (
        "No focus plan exists for today yet. Pick a few high-priority tasks and set one.",
        [
          "Review candidates with get_overview and get_upcoming_tasks.",
          "Set the plan with set_current_focus (pass a briefing for context).",
          "Time-block with propose_daily_schedule, then save_focus_schedule.",
        ])
    case "lists":
      return (
        "\(listCount) list(s) configured. Lists are folders: delete_list only works on an empty list — completed and cancelled tasks still count, so first move them elsewhere (move_task_to_list / batch_move_tasks) or delete them, or archive the list to retire it while keeping its tasks.",
        [
          "See all lists with get_lists; check load with get_list_health_snapshot.",
          "Create or restyle with create_list / update_list.",
          "Reorganize with move_task_to_list / batch_move_tasks; tidy tags with rename_tag.",
        ])
    case "focus_mode":
      return (
        "Focus mode runs a time-blocked schedule for the day.",
        [
          "Propose blocks with propose_daily_schedule (set include_calendar_events to honour meetings).",
          "Persist with save_focus_schedule; read it back with get_saved_focus_schedule.",
        ])
    case "weekly_review":
      return (
        "A weekly review should combine the user's daily reflections with task history. The MCP surface provides one compact brief plus rich task queries; deeper analysis should be done from list_tasks rather than fixed rule-based tools.",
        [
          "Start with get_weekly_brief for the sectioned activity brief.",
          "Use list_tasks with completed_from/completed_to, created_from/created_to, updated_from/updated_to, tags, and dependency filters for deeper analysis.",
          "Use get_review_history when the user wants to inspect what they wrote in daily reflections.",
        ])
    case "preferences":
      return (
        "\(configuredPreferenceCount) preference key(s) configured. Preferences cover working_hours, timezone, default_list_id, and ai_changelog_retention_policy.",
        [
          "Read with get_all_preferences or get_preference.",
          "Change with set_preference (values are JSON-encoded strings).",
          "Reset a key to its default with delete_preference.",
        ])
    case "data_and_export":
      return (
        "Export the workspace as JSON or CSV, or the calendar as ICS, for backup or migration.",
        [
          "Export entities with export_data (json or csv; scope with the entities list).",
          "Export the calendar with export_calendar_ics.",
          "Check sync health with get_sync_status.",
        ])
    default:  // overview
      return (
        runtimeSummary,
        [
          "Use the MCP host as the primary write surface.",
          "Call get_overview for a situational snapshot; use shape=full only when task objects are needed.",
          "Ask for a specific guide topic (e.g. task_management, weekly_review) for focused guidance.",
        ])
    }
  }
}
