import AppIntents
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI

/// Displays today's open tasks (due today + overdue) across systemSmall, Medium, and Large families.
public struct TodayWidgetView: View {
  public let snapshot: WidgetSnapshot
  public let family: WidgetFamilyKind
  public let staleAgeLabel: String?

  public init(snapshot: WidgetSnapshot, family: WidgetFamilyKind, staleAgeLabel: String? = nil) {
    self.snapshot = snapshot
    self.family = family
    self.staleAgeLabel = staleAgeLabel
  }

  private var rowLimit: Int {
    TodayWidgetLayout.rowLimit(for: family)
  }

  private var isInteractive: Bool {
    family == .systemMedium || family == .systemLarge
  }

  private var metrics: LorvexWidgetViewMetrics { .metrics(for: family) }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      taskList
      Spacer(minLength: 0)
      footer
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("widget.today.title", bundle: WidgetL10n.bundle)
        .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
        .lineLimit(1)
      Spacer(minLength: 8)
      Text("\(snapshot.todayTasks.count)")
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var taskList: some View {
    if snapshot.todayTasks.isEmpty {
      // Celebratory treatment matching the Habits widget's "all done" footer:
      // a done-tinted seal alongside the message, not bare text.
      HStack(spacing: 6) {
        Image(systemName: "checkmark.seal.fill")
          .foregroundStyle(LorvexDesign.Palette.done)
          .accessibilityHidden(true)
        Text("widget.today.all_done", bundle: WidgetL10n.bundle)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(snapshot.todayTasks.prefix(rowLimit), id: \.id) { task in
          TodayTaskRowView(task: task, interactive: isInteractive)
        }
      }
    }
  }

  private var footer: some View {
    let completed = snapshot.stats.completedTodayCount
    let remaining = snapshot.todayTasks.count
    return HStack(spacing: 8) {
      Text(TodayWidgetLayout.footerText(completed: completed, totalOpen: remaining, family: family))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 6)
      if let staleAgeLabel {
        WidgetStaleAgeLabel(staleAgeLabel)
      }
    }
  }
}

public enum TodayWidgetLayout {
  public static func rowLimit(for family: WidgetFamilyKind) -> Int {
    switch family {
    case .systemSmall: 3
    case .systemMedium: 4
    case .systemLarge: 8
    default: 3
    }
  }

  public static func hiddenTaskCount(total: Int, family: WidgetFamilyKind) -> Int {
    max(0, total - rowLimit(for: family))
  }

  public static func footerText(completed: Int, totalOpen: Int, family: WidgetFamilyKind) -> String {
    let hidden = hiddenTaskCount(total: totalOpen, family: family)
    if hidden > 0 {
      return String(
        localized: "widget.today.footer.more",
        defaultValue: "\(completed) completed · \(totalOpen) open · \(hidden) more",
        table: "Localizable",
        bundle: WidgetL10n.bundle)
    }
    return String(
      localized: "widget.today.footer",
      defaultValue: "\(completed) completed · \(totalOpen) open",
      table: "Localizable",
      bundle: WidgetL10n.bundle)
  }
}

// MARK: - Task row

struct TodayTaskRowView: View {
  let task: WidgetSnapshot.TodayTask
  var interactive: Bool

  var body: some View {
    HStack(spacing: 4) {
      Link(destination: task.taskURL) {
        taskLabel
      }
      if interactive {
        Spacer(minLength: 0)
        WidgetActionButton(
          intent: WidgetCompleteTaskIntent(taskID: task.id, title: task.title),
          systemName: "checkmark.circle.fill",
          accessibilityLabel: String(
            localized: "widget.action.complete.a11y",
            defaultValue: "Complete \(task.title)",
            table: "Localizable",
            bundle: WidgetL10n.bundle),
          tint: LorvexDesign.Palette.done
        )
      }
    }
  }

  private var taskLabel: some View {
    HStack(alignment: .top, spacing: 7) {
      // Colored priority dot, matching every other task surface, in place of the
      // old gray "P1" text (which also read as "P one" under VoiceOver).
      WidgetPriorityDot(color: lorvexWidgetPriorityDotTint(tier: task.priority))
      Text(task.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        // The task title is the user's private content on a Home Screen /
        // StandBy surface; redact it when the device locks.
        .privacySensitive()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(task.title)
  }
}
