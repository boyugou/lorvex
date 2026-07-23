import Foundation
import GRDB

@testable import LorvexStore

/// Builds a large, realistic, deterministic dataset directly via SQL INSERT
/// inside a single transaction. Going through the workflow ops per row would
/// both be slow at 10k and conflate seeding cost with the write benchmarks, so
/// the seeder writes rows directly (the task explicitly permits this).
///
/// Determinism: every value is drawn from a `SeededRNG` with a fixed seed and
/// every timestamp/date is derived from a fixed epoch — no `Date()`, no
/// `UUID()`. Two runs at the same `taskCount` produce byte-identical data.
enum BenchmarkSeeder {
  /// Anchor "today" for the dataset. All due/planned dates cluster around it.
  static let today = "2026-05-27"
  static let todayStartUtc = "2026-05-27T00:00:00.000Z"
  static let todayEndUtc = "2026-05-28T00:00:00.000Z"

  /// A fixed version stamp; HLC ordering doesn't matter for read benchmarks.
  private static let ver = "1716768000000_0000_dec0000100000001"

  struct SeedStats {
    let tasks: Int
    let lists: Int
    let tags: Int
    let dependencies: Int
    let checklistItems: Int
    let reminders: Int
    let calendarEvents: Int
    let habits: Int
  }

  /// Seed the store with `taskCount` tasks plus proportional related rows.
  @discardableResult
  static func seed(_ store: LorvexStore, taskCount: Int) throws -> SeedStats {
    var rng = SeededRNG(seed: 0xC0FFEE_1234_5678)

    let listCount = max(1, taskCount / 50)  // ~50 tasks per list
    let tagCount = max(1, taskCount / 100)  // ~100 tasks per tag
    let habitCount = max(1, taskCount / 200)
    let eventCount = taskCount / 4  // a quarter as many calendar events

    var stats = (deps: 0, checks: 0, reminders: 0)

    try store.writer.write { db in
      // Calendar timeline search reads a timezone-anchored expansion; set it.
      try db.execute(
        sql: "INSERT INTO preferences (key, value, version, updated_at) "
          + "VALUES ('timezone', ?, ?, ?) "
          + "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        arguments: ["\"UTC\"", ver, todayStartUtc])

      // ---- lists ----
      // The schema seeds `inbox`; add the rest.
      try db.execute(
        sql: "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('inbox', 'Inbox', ?, ?, ?)",
        arguments: [ver, todayStartUtc, todayStartUtc])
      var listIds = ["inbox"]
      for i in 0..<listCount {
        let id = "list-\(i)"
        listIds.append(id)
        try db.execute(
          sql: "INSERT INTO lists (id, name, version, created_at, updated_at) "
            + "VALUES (?, ?, ?, ?, ?)",
          arguments: [id, "Project \(i)", ver, todayStartUtc, todayStartUtc])
      }

      // ---- tags ----
      var tagIds: [String] = []
      let tagWords = ["work", "home", "urgent", "later", "errand", "study", "health", "money"]
      for i in 0..<tagCount {
        let id = "tag-\(i)"
        tagIds.append(id)
        let word = tagWords[i % tagWords.count]
        let lookup = "\(word)\(i)"
        try db.execute(
          sql: "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) "
            + "VALUES (?, ?, ?, ?, ?, ?)",
          arguments: [id, "\(word.capitalized) \(i)", lookup, ver, todayStartUtc, todayStartUtc])
      }

      // ---- tasks ----
      let titleNouns = [
        "report", "review", "groceries", "invoice", "meeting", "design",
        "refactor", "email", "proposal", "budget", "plan", "ticket",
      ]
      let titleVerbs = ["Write", "Finish", "Send", "Draft", "Plan", "Review", "Fix", "Prepare"]
      let statuses = ["open", "open", "open", "open", "completed", "someday", "cancelled"]
      let deferReasons = ["not_today", "blocked", "low_energy", "needs_breakdown", "needs_info"]

      var taskIds: [String] = []
      taskIds.reserveCapacity(taskCount)

      for i in 0..<taskCount {
        let id = String(format: "task-%07d", i)
        taskIds.append(id)
        let listId = rng.pick(listIds)
        let status = rng.pick(statuses)
        let verb = rng.pick(titleVerbs)
        let noun = rng.pick(titleNouns)
        // ~10% of titles carry a CJK marker so the trigram/CJK search path has
        // real data to match (`报告` = "report").
        let cjk = rng.bool(0.1) ? " 报告会议" : ""
        let title = "\(verb) \(noun) #\(i)\(cjk)"
        let priority: Int? = rng.bool(0.6) ? (rng.int(3) + 1) : nil

        // Dates cluster around `today` so the today/overdue/upcoming buckets
        // are all meaningfully populated.
        let dayOffset = rng.int(60) - 30  // -30..+29
        let dueDate: String? = rng.bool(0.5) ? dateOffset(dayOffset) : nil
        let plannedDate: String? = rng.bool(0.3) ? dateOffset(rng.int(40) - 10) : nil

        let completedAt: String? =
          status == "completed" ? timestampOffset(rng.int(30)) : nil
        let body: String? = rng.bool(0.4) ? "Details about \(noun) number \(i) and follow-up." : nil
        let aiNotes: String? = rng.bool(0.2) ? "AI summary: \(noun) priority context \(i)." : nil
        let estimated: Int? = rng.bool(0.5) ? (rng.int(8) + 1) * 15 : nil
        let archived: String? = (status != "completed" && rng.bool(0.05))
          ? timestampOffset(rng.int(20)) : nil
        let deferCount = rng.bool(0.15) ? rng.int(4) : 0
        let deferReason: String? = deferCount > 0 ? rng.pick(deferReasons) : nil
        let lastDeferredAt: String? = deferCount > 0 ? timestampOffset(rng.int(10)) : nil

        try db.execute(
          sql: """
            INSERT INTO tasks (
              id, title, body, ai_notes, status, list_id, priority,
              due_date, planned_date, estimated_minutes,
              version, created_at, updated_at, completed_at,
              archived_at, defer_count, last_deferred_at, last_defer_reason
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
          arguments: [
            id, title, body, aiNotes, status, listId, priority,
            dueDate, plannedDate, estimated,
            ver, timestampOffset(rng.int(90) + 30), todayStartUtc, completedAt,
            archived, deferCount, lastDeferredAt, deferReason,
          ])

        // ---- task_tags (~1.5 tags per task on average) ----
        if !tagIds.isEmpty {
          let n = rng.int(3)
          var used = Set<String>()
          for _ in 0..<n {
            let tagId = rng.pick(tagIds)
            if used.insert(tagId).inserted {
              try db.execute(
                sql: "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) "
                  + "VALUES (?, ?, ?, ?)",
                arguments: [id, tagId, ver, todayStartUtc])
            }
          }
        }

        // ---- checklist items (~30% of tasks, up to 5 items) ----
        if rng.bool(0.3) {
          let items = rng.int(5) + 1
          for p in 0..<items {
            let done: String? = rng.bool(0.4) ? timestampOffset(rng.int(10)) : nil
            try db.execute(
              sql: "INSERT INTO task_checklist_items "
                + "(id, task_id, position, text, completed_at, version, created_at, updated_at) "
                + "VALUES (?,?,?,?,?,?,?,?)",
              arguments: [
                "\(id)-ck\(p)", id, p, "Step \(p) for \(noun)", done, ver, todayStartUtc,
                todayStartUtc,
              ])
            stats.checks += 1
          }
        }

        // ---- reminders (~25% of tasks) ----
        if rng.bool(0.25) {
          try db.execute(
            sql: "INSERT INTO task_reminders "
              + "(id, task_id, reminder_at, version, created_at, original_local_time, original_tz) "
              + "VALUES (?,?,?,?,?,?,?)",
            arguments: [
              "\(id)-rm", id, timestampOffset(-(rng.int(10) + 1)), ver, todayStartUtc, "09:00",
              "UTC",
            ])
          stats.reminders += 1
        }
      }

      // ---- dependencies: a dense graph among the first chunk of tasks ----
      // Edge i -> earlier task keeps the graph acyclic (depends_on points back).
      let depPool = min(taskCount, 2_000)
      for i in 1..<depPool {
        // ~1.5 incoming edges per node on average within the pool.
        let edges = rng.int(3)
        var used = Set<Int>()
        for _ in 0..<edges {
          let target = rng.int(i)  // strictly earlier → acyclic
          if used.insert(target).inserted {
            try db.execute(
              sql: "INSERT OR IGNORE INTO task_dependencies "
                + "(task_id, depends_on_task_id, version, created_at) VALUES (?,?,?,?)",
              arguments: [taskIds[i], taskIds[target], ver, todayStartUtc])
            stats.deps += 1
          }
        }
      }

      // ---- habits + completions ----
      for i in 0..<habitCount {
        let id = "habit-\(i)"
        try db.execute(
          sql: "INSERT INTO habits (id, name, lookup_key, version, created_at, updated_at) "
            + "VALUES (?, ?, ?, ?, ?, ?)",
          arguments: [id, "Habit \(i)", "habit\(i)", ver, todayStartUtc, todayStartUtc])
        // ~20 completions each across recent days.
        for d in 0..<20 {
          try db.execute(
            sql: "INSERT OR IGNORE INTO habit_completions "
              + "(habit_id, completed_date, version, created_at, updated_at) VALUES (?,?,?,?,?)",
            arguments: [id, dateOffset(-d), ver, todayStartUtc, todayStartUtc])
        }
      }

      // ---- calendar events (some recurring) ----
      for i in 0..<eventCount {
        let id = "event-\(i)"
        let dayOffset = rng.int(60) - 30
        let startDate = dateOffset(dayOffset)
        let allDay = rng.bool(0.2)
        let startHour = 8 + rng.int(10)
        let startTime: String? = allDay ? nil : String(format: "%02d:00", startHour)
        let endTime: String? = allDay ? nil : String(format: "%02d:00", min(startHour + 1, 23))
        let recurring = rng.bool(0.15)
        let recurrence: String? = recurring ? "{\"FREQ\":\"WEEKLY\"}" : nil
        try db.execute(
          sql: "INSERT INTO calendar_events "
            + "(id, title, start_date, start_time, end_date, end_time, all_day, recurrence, "
            + " recurrence_generation, recurrence_topology_version, content_version, version, "
            + " created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
          arguments: [
            id, "Event \(i)", startDate, startTime, startDate, endTime, allDay ? 1 : 0,
            recurrence, recurring ? ver : nil, ver, ver, ver, todayStartUtc, todayStartUtc,
          ])
      }

      // ---- trigram FTS index: not auto-installed at open; build it so the
      // CJK/substring search path is exercised against real data. ----
      try FtsRepo.installTasksTrigramTriggers(db)
      try FtsRepo.rebuildTasksTrigram(db)
    }

    // Ensure the SQLite query planner has fresh statistics for EQP audits.
    try store.writer.write { db in try db.execute(sql: "ANALYZE") }

    return SeedStats(
      tasks: taskCount, lists: listCount + 1, tags: tagCount,
      dependencies: stats.deps, checklistItems: stats.checks, reminders: stats.reminders,
      calendarEvents: eventCount, habits: habitCount)
  }

  // MARK: - deterministic date/time helpers

  private static let epoch: Date = {
    var c = DateComponents()
    c.year = 2026; c.month = 5; c.day = 27
    c.hour = 0; c.minute = 0; c.second = 0
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
  }()

  /// `YYYY-MM-DD` for `today + days`.
  static func dateOffset(_ days: Int) -> String {
    let d = epoch.addingTimeInterval(Double(days) * 86_400)
    return isoDate(d)
  }

  /// RFC 3339 UTC timestamp for `today + days` at noon.
  static func timestampOffset(_ days: Int) -> String {
    let d = epoch.addingTimeInterval(Double(days) * 86_400 + 43_200)
    return isoTimestamp(d)
  }

  private static func isoDate(_ d: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
  }

  private static func isoTimestamp(_ d: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
    return String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
      c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
  }
}
