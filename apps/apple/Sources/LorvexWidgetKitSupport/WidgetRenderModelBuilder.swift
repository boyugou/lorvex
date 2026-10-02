import Foundation
import LorvexCore

/// Turns a timeline entry into what a widget family draws: the lead task at
/// the entry's clock, the rows after it, and the state and status lines.
public struct WidgetRenderModelBuilder: Sendable {
  public init() {}

  public func model(
    entry: WidgetTimelineEntry,
    family: WidgetFamilyKind,
    statusText: String
  ) -> WidgetRenderModel {
    switch entry.state {
    case .snapshot(let snapshot, let freshness):
      return snapshotModel(
        snapshot: snapshot, freshness: freshness, family: family, statusText: statusText,
        date: entry.date)
    case .fallback:
      return WidgetRenderModel(
        family: family,
        state: .fallback,
        headline: Self.appName,
        subheadline: String(
          localized: "widget.fallback.unavailable",
          defaultValue: "Widget data is not available.",
          table: "Localizable",
          bundle: WidgetSupportL10n.bundle),
        statusText: statusText,
        urlString: Self.todayURLString
      )
    }
  }

  private func snapshotModel(
    snapshot: WidgetSnapshot,
    freshness: WidgetSnapshotFreshness,
    family: WidgetFamilyKind,
    statusText: String,
    date: Date
  ) -> WidgetRenderModel {
    let nowMinutes = WidgetTodayGlance.minutes(at: date, timezoneName: snapshot.timezone)
    let glance = WidgetTodayGlance.build(tasks: snapshot.tasks, nowMinutes: nowMinutes)
    let logicalDay = snapshot.logicalDay
    let lead = glance.lead.map { leadRender($0, glance: glance, logicalDay: logicalDay) }
    let rowBudget = glance.lead == nil ? family.maxTaskRowsWithoutLead : family.maxTaskRows
    let rows = glance.rest.prefix(rowBudget).map {
      taskRow($0, nowMinutes: nowMinutes, logicalDay: logicalDay)
    }
    let upcomingCount = max(
      glance.rest.count, snapshot.stats.todayCount - (glance.lead == nil ? 0 : 1))
    let remainingCount = upcomingCount + (glance.lead == nil ? 0 : 1)
    let state: WidgetRenderState =
      switch freshness {
      case .stale:
        .stale
      case .fresh, .warning, .unknownTimestamp:
        remainingCount == 0 ? .empty : .content
      }
    let briefing = snapshot.briefing?.trimmingCharacters(in: .whitespacesAndNewlines)

    return WidgetRenderModel(
      family: family,
      state: state,
      headline: headline(lead: lead, family: family, scope: snapshot.scopeList),
      subheadline: subheadline(state: state),
      briefing: briefing?.isEmpty == false ? briefing : nil,
      statusText: statusText,
      staleAgeLabel: freshness.staleAgeLabel(),
      completedCount: snapshot.stats.completedTodayCount,
      lead: lead,
      taskRows: rows,
      upcomingCount: upcomingCount,
      dayLeft: remainingCount > 0 ? Self.dayLeft(remainingCount) : nil,
      dayWork: remainingCount > 0 ? Self.dayWork(glance.workMinutes) : nil,
      urlString: family == .accessoryInline
        ? (lead?.urlString ?? Self.todayURLString) : Self.todayURLString
    )
  }

  /// "4 left today".
  static func dayLeft(_ remaining: Int) -> String {
    String(
      localized: "widget.day.left", defaultValue: "\(remaining) left today",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  /// "4 left", under a "Today" title that already names the day.
  static func dayLeftUnderTitle(_ remaining: Int) -> String {
    String(
      localized: "widget.day.left.under_title", defaultValue: "\(remaining) left",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  /// "about 3 hr", or nil when no task carries an estimate or a time. Work
  /// under an hour is counted in minutes; longer work in hours, rounded to the
  /// half hour.
  static func dayWork(_ workMinutes: Int?) -> String? {
    guard let workMinutes, workMinutes > 0 else { return nil }
    let length =
      workMinutes < 60
      ? LorvexDurationFormat.minutes(workMinutes)
      : LorvexDurationFormat.hours(Int((Double(workMinutes) / 30).rounded()) * 30)
    return String(
      localized: "widget.day.work", defaultValue: "about \(length)",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  /// The inline family has one line, so its headline is the lead task's title;
  /// every other family titles itself with the list it is configured to show,
  /// or "Today".
  private func headline(
    lead: WidgetLeadRender?, family: WidgetFamilyKind, scope: WidgetSnapshot.ListSummary?
  ) -> String {
    if family == .accessoryInline, let lead {
      return lead.title
    }
    if let name = scope?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    return String(
      localized: "widget.title.today", defaultValue: "Today",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  private func subheadline(state: WidgetRenderState) -> String {
    switch state {
    case .stale:
      String(
        localized: "widget.subhead.stale", defaultValue: "Showing the latest saved list.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    case .empty, .content, .fallback:
      String(
        localized: "widget.subhead.empty", defaultValue: "Nothing left for today.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    }
  }

  /// The lead task with its line: "Until" and the end while its time runs, its
  /// time while one is saved (the next time), else that it is overdue, else
  /// that it is started. An untimed task that is not started never leads. The
  /// short line is the same fact in a few words for the one-line families.
  private func leadRender(
    _ item: WidgetTodayGlance.Item, glance: WidgetTodayGlance, logicalDay: String?
  ) -> WidgetLeadRender {
    let task = item.task
    let isOverdue = Self.isOverdue(task, logicalDay: logicalDay)
    var line: String?
    var shortLine: String?
    if glance.isLeadRunning, let time = item.time {
      line = Self.until(time.upperBound)
      shortLine = line
    } else if let time = item.time {
      line = lorvexClockRangeLabel(startMinutes: time.lowerBound, endMinutes: time.upperBound)
      shortLine = Self.clock(time.lowerBound)
    } else if isOverdue {
      line = Self.overdue
      shortLine = line
    } else if task.isStarted {
      if let minutes = task.estimatedMinutes, minutes > 0 {
        line = String(
          localized: "widget.lead.started_about",
          defaultValue: "Started · about \(LorvexDurationFormat.minutes(minutes))",
          table: "Localizable", bundle: WidgetSupportL10n.bundle)
      } else {
        line = Self.started
      }
      shortLine = Self.started
    }
    return WidgetLeadRender(
      id: item.id,
      title: task.title,
      line: line,
      shortLine: shortLine,
      progress: glance.progress,
      isRunning: glance.isLeadRunning,
      minutesLeft: glance.minutesLeft,
      isOverdue: isOverdue,
      urlString: Self.taskURLString(taskID: item.id))
  }

  /// A row under the lead: "Until" and the end while its time runs, else its
  /// time's start, else "Overdue", else "Started", else its estimate.
  private func taskRow(
    _ item: WidgetTodayGlance.Item, nowMinutes: Int, logicalDay: String?
  ) -> WidgetTaskRenderRow {
    var metadata: String?
    var tone = WidgetTaskRenderRow.Tone.plain
    if let time = item.time, time.contains(nowMinutes) {
      metadata = Self.until(time.upperBound)
      tone = .running
    } else if let time = item.time {
      metadata = Self.clock(time.lowerBound)
    } else if Self.isOverdue(item.task, logicalDay: logicalDay) {
      metadata = Self.overdue
      tone = .overdue
    } else if item.task.isStarted {
      metadata = Self.started
      tone = .started
    } else if let minutes = item.task.estimatedMinutes, minutes > 0 {
      metadata = LorvexDurationFormat.minutes(minutes)
    }
    return WidgetTaskRenderRow(
      id: item.id,
      title: item.task.title,
      metadata: metadata,
      tone: tone,
      urlString: Self.taskURLString(taskID: item.id),
      priority: item.task.priority.flatMap(LorvexTask.Priority.init(tier:)))
  }

  /// A due date before the snapshot's day. Both are `YYYY-MM-DD` keys, so they
  /// compare as strings.
  private static func isOverdue(_ task: WidgetSnapshot.TodayTask, logicalDay: String?) -> Bool {
    guard let due = task.dueDate, let logicalDay else { return false }
    return due < logicalDay
  }

  private static func until(_ minutes: Int) -> String {
    String(
      localized: "widget.lead.until", defaultValue: "Until \(clock(minutes))",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  private static var overdue: String {
    String(
      localized: "widget.task.overdue", defaultValue: "Overdue",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  private static var started: String {
    String(
      localized: "widget.task.started", defaultValue: "Started",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  private static func clock(_ minutes: Int) -> String {
    lorvexClockTimeLabel(minutes: minutes)
  }

  private static var appName: String {
    String(
      localized: "widget.title.lorvex", defaultValue: "Lorvex",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
  }

  private static let todayURLString = LorvexDeepLinkContract.destinationURLString(.today)

  private static func taskURLString(taskID: String) -> String {
    LorvexDeepLinkContract.taskURLString(taskID)
  }
}
