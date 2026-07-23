import Foundation
import LorvexCore

public struct WidgetRenderModelBuilder: Sendable {
  public init() {}

  public func model(
    entry: WidgetTimelineEntry,
    family: WidgetFamilyKind,
    statusText: String
  ) -> WidgetRenderModel {
    switch entry.state {
    case .snapshot(let snapshot, let freshness):
      return snapshotModel(snapshot: snapshot, freshness: freshness, family: family, statusText: statusText)
    case .fallback:
      return WidgetRenderModel(
        family: family,
        state: .fallback,
        headline: String(
          localized: "widget.title.lorvex", defaultValue: "Lorvex",
          table: "Localizable", bundle: WidgetSupportL10n.bundle),
        subheadline: String(
          localized: "widget.fallback.unavailable",
          defaultValue: "Widget data is not available.",
          table: "Localizable",
          bundle: WidgetSupportL10n.bundle),
        statusText: statusText,
        staleAgeLabel: nil,
        focusCountText: String(
          localized: "widget.count.focus_format", defaultValue: "\(0) in focus",
          table: "Localizable", bundle: WidgetSupportL10n.bundle),
        focusCount: 0,
        attentionCountText: nil,
        taskRows: [],
        urlString: Self.todayURLString
      )
    }
  }

  private func snapshotModel(
    snapshot: WidgetSnapshot,
    freshness: WidgetSnapshotFreshness,
    family: WidgetFamilyKind,
    statusText: String
  ) -> WidgetRenderModel {
    let focusTasks = snapshot.actionableFocusTasks
    let rows = Array(focusTasks.prefix(family.maxTaskRows)).map(taskRow)
    let state: WidgetRenderState =
      switch freshness {
      case .stale:
        .stale
      case .fresh, .warning, .unknownTimestamp:
        rows.isEmpty ? .empty : .content
      }
    let headline = headline(focusTasks: focusTasks, family: family)
    let subheadline = subheadline(for: snapshot, state: state)

    return WidgetRenderModel(
      family: family,
      state: state,
      headline: headline,
      subheadline: subheadline,
      statusText: statusText,
      staleAgeLabel: freshness.staleAgeLabel(),
      focusCountText: String(
        localized: "widget.count.focus_format",
        defaultValue: "\(snapshot.stats.focusCount) in focus",
        table: "Localizable", bundle: WidgetSupportL10n.bundle),
      focusCount: snapshot.stats.focusCount,
      completedCount: snapshot.stats.completedTodayCount,
      attentionCountText: snapshot.stats.attentionCount > 0
        ? String(
          localized: "widget.count.attention_format",
          defaultValue: "\(snapshot.stats.attentionCount) due",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)
        : nil,
      taskRows: rows,
      urlString: widgetURLString(focusTasks: focusTasks, family: family)
    )
  }

  private func headline(focusTasks: [WidgetSnapshot.FocusTask], family: WidgetFamilyKind) -> String {
    if family == .accessoryInline {
      if let firstTask = focusTasks.first {
        return firstTask.title
      }
      return String(
        localized: "widget.title.lorvex", defaultValue: "Lorvex",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    }
    // "Focus", not "Today": this model backs the Lorvex Focus widget and the
    // Today widget's "Focus Queue" display mode, both of which render the
    // actionable focus-task queue rather than the full today list. The standalone
    // Today widget (`TodayWidgetView`) uses its own "Today" header, so the two
    // widget kinds never show the same title in the widget gallery preview.
    return String(
      localized: "widget.title.focus", defaultValue: "Focus",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  private func subheadline(for snapshot: WidgetSnapshot, state: WidgetRenderState) -> String {
    if state == .empty {
      return String(
        localized: "widget.subhead.empty", defaultValue: "No focus tasks yet.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    }
    if state == .stale {
      return String(
        localized: "widget.subhead.stale", defaultValue: "Showing the latest saved plan.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    }
    if let briefing = snapshot.briefing?.trimmingCharacters(in: .whitespacesAndNewlines),
      !briefing.isEmpty
    {
      return briefing
    }
    return String(
      localized: "widget.subhead.default", defaultValue: "Focus on the next useful step.",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  private func taskRow(_ task: WidgetSnapshot.FocusTask) -> WidgetTaskRenderRow {
    WidgetTaskRenderRow(
      id: task.id,
      title: task.title,
      metadata: taskMetadata(task),
      priorityLabel: task.priority.flatMap(priorityLabel),
      priorityTier: task.priority,
      urlString: Self.taskURLString(taskID: task.id)
    )
  }

  private func widgetURLString(focusTasks: [WidgetSnapshot.FocusTask], family: WidgetFamilyKind) -> String {
    if family == .accessoryInline, let firstTask = focusTasks.first {
      return Self.taskURLString(taskID: firstTask.id)
    }
    return Self.todayURLString
  }

  private func taskMetadata(_ task: WidgetSnapshot.FocusTask) -> String? {
    var parts: [String] = []
    if let estimatedMinutes = task.estimatedMinutes, estimatedMinutes > 0 {
      parts.append(
        String(
          format: String(
            localized: "widget.task.duration_minutes", defaultValue: "%lld min",
            table: "Localizable", bundle: WidgetSupportL10n.bundle),
          estimatedMinutes))
    }
    if let dueDate = task.dueDate, !dueDate.isEmpty {
      parts.append(formattedDueDate(dueDate))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private func priorityLabel(_ priority: Int) -> String? {
    switch priority {
    case 1:
      String(
        localized: "widget.task.priority.p1", defaultValue: "Priority 1",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    case 2:
      String(
        localized: "widget.task.priority.p2", defaultValue: "Priority 2",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    case 3:
      String(
        localized: "widget.task.priority.p3", defaultValue: "Priority 3",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    default:
      nil
    }
  }

  private func formattedDueDate(_ dueDate: String) -> String {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: dueDate) else {
      return dueDate
    }
    return Self.mediumDueDateFormatter.string(from: date)
  }

  private static let todayURLString = LorvexDeepLinkContract.destinationURLString(.today)

  private static let mediumDueDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  private static func taskURLString(taskID: String) -> String {
    LorvexDeepLinkContract.taskURLString(taskID)
  }
}
