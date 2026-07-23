import Foundation

// MARK: - Task

/// Renders a `LorvexTask` as a self-contained markdown document for sharing.
///
/// All fields are rendered in declaration order; optional fields are omitted
/// when nil or empty. The checklist renders each item as a GitHub-flavored task
/// list entry (`- [x]` / `- [ ]`).
public enum LorvexTaskMarkdownExport: Sendable {
  public static func render(_ task: LorvexTask) -> String {
    var lines: [String] = []
    lines.append("# \(task.title)")
    lines.append("")
    lines.append("**Status:** \(task.status.rawValue)  ")
    lines.append("**Priority:** \(task.priority.rawValue)")

    if let due = task.dueDate {
      let formatted = LorvexDateFormatters.iso8601.string(from: due)
      lines.append("**Due:** \(formatted)")
    }

    if let minutes = task.estimatedMinutes {
      lines.append("**Estimate:** \(minutes) min")
    }

    if !task.tags.isEmpty {
      lines.append("**Tags:** \(task.tags.joined(separator: ", "))")
    }

    if !task.notes.isEmpty {
      lines.append("")
      lines.append("## Notes")
      lines.append("")
      lines.append(task.notes)
    }

    if let aiNotes = task.aiNotes, !aiNotes.isEmpty {
      lines.append("")
      lines.append("## Assistant Context")
      lines.append("")
      lines.append(aiNotes)
    }

    if !task.checklistItems.isEmpty {
      lines.append("")
      lines.append("## Checklist")
      lines.append("")
      let sorted = task.checklistItems.sorted { $0.position < $1.position }
      for item in sorted {
        let mark = item.completedAt != nil ? "x" : " "
        lines.append("- [\(mark)] \(item.text)")
      }
    }

    return lines.joined(separator: "\n")
  }
}

// MARK: - Daily Review

/// Renders a `DailyReviewEntry` as a self-contained markdown document for sharing.
///
/// Mood and energy are rendered as numeric values (1–5). Optional text fields
/// (wins, blockers, learnings) are omitted when nil or blank.
public enum LorvexDailyReviewMarkdownExport: Sendable {
  public static func render(_ review: DailyReviewEntry) -> String {
    var lines: [String] = []
    lines.append("# Daily Review — \(review.date)")
    lines.append("")

    if let mood = review.mood {
      lines.append("**Mood:** \(mood)/5")
    }
    if let energy = review.energyLevel {
      lines.append("**Energy:** \(energy)/5")
    }

    if !review.summary.isEmpty {
      lines.append("")
      lines.append("## Summary")
      lines.append("")
      lines.append(review.summary)
    }

    if let wins = review.wins, !wins.isEmpty {
      lines.append("")
      lines.append("## Wins")
      lines.append("")
      lines.append(wins)
    }

    if let blockers = review.blockers, !blockers.isEmpty {
      lines.append("")
      lines.append("## Blockers")
      lines.append("")
      lines.append(blockers)
    }

    if let learnings = review.learnings, !learnings.isEmpty {
      lines.append("")
      lines.append("## Learnings")
      lines.append("")
      lines.append(learnings)
    }

    return lines.joined(separator: "\n")
  }
}

// MARK: - Weekly Review

/// Renders a `WeeklyReviewSnapshot` as a self-contained markdown document for sharing.
///
/// Metrics table is always rendered. Task lists (top completed, frequently deferred)
/// are omitted when empty.
public enum LorvexWeeklyReviewMarkdownExport: Sendable {
  public static func render(_ snapshot: WeeklyReviewSnapshot) -> String {
    var lines: [String] = []
    lines.append("# Weekly Review — \(snapshot.windowTitle)")
    lines.append("")
    lines.append("## Metrics")
    lines.append("")
    lines.append("| Metric | Count |")
    lines.append("|--------|-------|")
    lines.append("| Completed | \(snapshot.completedThisWeek) |")
    lines.append("| Created | \(snapshot.createdThisWeek) |")
    lines.append("| Overdue | \(snapshot.overdueOpen) |")
    lines.append("| Deferred | \(snapshot.deferredOpen) |")
    lines.append("| Someday | \(snapshot.someday) |")

    if let ratio = snapshot.estimateCoverageRatio {
      let pct = Int((ratio * 100).rounded())
      lines.append("| Estimate Coverage | \(pct)% |")
    }

    if !snapshot.topCompleted.isEmpty {
      lines.append("")
      lines.append("## Completed This Week")
      lines.append("")
      for task in snapshot.topCompleted {
        lines.append("- \(task.title)")
      }
    }

    if !snapshot.frequentlyDeferred.isEmpty {
      lines.append("")
      lines.append("## Frequently Deferred")
      lines.append("")
      for task in snapshot.frequentlyDeferred {
        lines.append("- \(task.title) (deferred \(task.deferCount)×)")
      }
    }

    return lines.joined(separator: "\n")
  }
}
