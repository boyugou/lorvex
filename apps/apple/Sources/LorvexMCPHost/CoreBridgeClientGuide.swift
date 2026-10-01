import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadGuide(topic: String?) async throws -> Value {
    let setup = try await service.loadRuntimeDiagnostics().setup
    // Live state the guidance folds in: memory depth, configured preference
    // keys, and whether today has a briefing.
    let memory = try await service.loadMemory()
    let preferences = try await service.getAllPreferences()
    let hasBriefing = try await service.getOverviewCompact().hasBriefing
    let configuredPreferences = preferences.values.keys.sorted().map(Value.string)

    // Unrecognized topics resolve to the overview, so the copy always matches
    // the topic the response names.
    let resolvedTopic = Self.canonicalGuideTopic(topic)
    let copy = Self.guideCopy(
      topic: resolvedTopic,
      setupCompleted: setup.setupCompleted,
      taskCount: setup.taskCount,
      listCount: setup.listCount,
      hasBriefing: hasBriefing,
      memoryCount: memory.entries.count,
      configuredPreferenceCount: configuredPreferences.count)
    return .object([
      "topic": .string(resolvedTopic),
      "state": .object([
        "setup_completed": .bool(setup.setupCompleted),
        "task_count": .int(setup.taskCount),
        "list_count": .int(setup.listCount),
        "has_briefing": .bool(hasBriefing),
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
      "overview", "getting_started", "task_management", "planning",
      "lists", "weekly_review", "preferences", "data_and_export",
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
    setupCompleted: Bool,
    taskCount: Int,
    listCount: Int,
    hasBriefing: Bool,
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
            "Plan the day with update_task (planned_date), then write a set_daily_briefing.",
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
        "Tasks carry priority, planned_date with an optional time on that day (planned_start_time, planned_end_time), tags, dependencies, a checklist, reminders, and recurrence. Status transitions go through complete/cancel/reopen/defer and start/pause — never update_task. start_task marks work in_progress (an actionable state that surfaces wherever open does); pause_task clears it.",
        [
          "Capture with create_task / batch_create_tasks; enrich fields with update_task.",
          "Break work down with add_task_checklist_item; set deadlines with add_task_reminder.",
          "Change status with complete_task / cancel_task / reopen_task / defer_task; mark active work with start_task and clear it with pause_task.",
          "Surface load with get_upcoming_tasks, get_deferred_tasks, and search_tasks.",
        ])
    case "planning":
      let day =
        "Today lists every task that is overdue, on the day, or started, started tasks first; "
        + "planned_date, when set, decides a task's day, otherwise due_date does."
      let arrange =
        "Put work on a day with update_task or batch_update_tasks (planned_date); move what no "
        + "longer fits with defer_task or batch_defer_tasks, which count the deferral."
      let times =
        "Offer times only when the user wants a timetable: propose_daily_schedule, then "
        + "save_daily_schedule; read the day's times with get_daily_schedule, and time one task "
        + "with update_task (planned_start_time, planned_end_time)."
      if hasBriefing {
        return (
          "\(day) Today already has a briefing; keep it current when the day changes.",
          [
            "Read the day with get_overview shape=full: today is the list, briefing the text.",
            arrange,
            "Rewrite the briefing with set_daily_briefing after changing the day.",
            times,
          ])
      }
      return (
        "\(day) Today has no briefing yet.",
        [
          "Read the day with get_overview shape=full and the free time with get_calendar_timeline.",
          arrange,
          "Write two or three sentences with set_daily_briefing: what matters and why, and what you moved.",
          times,
        ])
    case "lists":
      return (
        "\(listCount) list(s) configured. Lists are folders: delete_list only works on an empty list — completed and cancelled tasks still count, so first move them elsewhere (move_task_to_list / batch_move_tasks) or delete them, or archive the list to retire it while keeping its tasks.",
        [
          "See all lists with get_lists; check load with get_list_health_snapshot.",
          "Create or restyle with create_list / update_list.",
          "Reorganize with move_task_to_list / batch_move_tasks; tidy tags with rename_tag.",
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
      let setupNote = setupCompleted ? "" : " Setup isn't complete yet."
      return (
        "Lorvex holds \(taskCount) task(s) in \(listCount) list(s).\(setupNote)",
        [
          "Use the MCP host as the primary write surface.",
          "Call get_overview for a situational snapshot; use shape=full only when task objects are needed.",
          "Ask for a specific guide topic (e.g. task_management, weekly_review) for focused guidance.",
        ])
    }
  }
}
