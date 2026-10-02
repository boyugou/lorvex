import Foundation
import LorvexCore

public enum WidgetFamilyKind: Equatable, Sendable {
  case systemSmall
  case systemMedium
  case systemLarge
  case accessoryInline
  case accessoryRectangular
  case accessoryCircular

  /// How many tasks the family lists under the lead task, at most. The small
  /// and glance families say only how many more there are. Medium and large
  /// draw as many of these as their height holds, so a taller widget (large
  /// on the Mac desktop) shows more than a shorter one.
  public var maxTaskRows: Int {
    switch self {
    case .accessoryInline, .accessoryCircular, .systemSmall:
      0
    case .accessoryRectangular:
      1
    case .systemMedium:
      2
    case .systemLarge:
      6
    }
  }

  /// How many tasks the family lists when no task leads: the lead block's room
  /// goes to one more row, and the small and rectangular families, which
  /// otherwise show only the lead, list the top two.
  public var maxTaskRowsWithoutLead: Int {
    switch self {
    case .accessoryInline, .accessoryCircular:
      0
    case .systemSmall, .accessoryRectangular:
      2
    case .systemMedium:
      3
    case .systemLarge:
      7
    }
  }
}

public enum WidgetRenderState: Equatable, Sendable {
  case content
  case empty
  case stale
  case fallback
}

/// The lead task as a widget draws it: its circle (a ring that fills while its
/// time runs), its title, and one line about it, all resolved for the entry's
/// date.
public struct WidgetLeadRender: Equatable, Sendable {
  public let id: String
  public let title: String
  /// The line under the title: "Until 3:00 PM" while its time runs, its time
  /// ("2:00 – 3:00 PM"), "Overdue", "Started", its estimate ("About 45 min"),
  /// or nil when none applies.
  public let line: String?
  /// The same fact in a few words, leading the one-line families ("Until
  /// 3:00 PM", "2:00 PM", "Overdue", "Started", "45 min").
  public let shortLine: String?
  /// How much of the running time has passed; 0 unless ``isRunning``.
  public let progress: Double
  /// True while the task's saved time contains the clock.
  public let isRunning: Bool
  public let minutesLeft: Int?
  public let isOverdue: Bool
  public let urlString: String

  public init(
    id: String, title: String, line: String?, shortLine: String?,
    progress: Double, isRunning: Bool, minutesLeft: Int?, isOverdue: Bool, urlString: String
  ) {
    self.id = id
    self.title = title
    self.line = line
    self.shortLine = shortLine
    self.progress = min(max(progress, 0), 1)
    self.isRunning = isRunning
    self.minutesLeft = minutesLeft
    self.isOverdue = isOverdue
    self.urlString = urlString
  }
}

/// One task under the lead.
public struct WidgetTaskRenderRow: Equatable, Sendable, Identifiable {
  /// How the metadata column reads: plain secondary text, the accent for a
  /// running time or a started task, or red for a missed deadline.
  public enum Tone: Equatable, Sendable {
    case plain
    case running
    case started
    case overdue
  }

  public let id: String
  public let title: String
  /// "Until" and the end while the task's time runs, else the time's start as
  /// a clock label, else "Overdue", else "Started", else the estimate, else nil.
  public let metadata: String?
  public let tone: Tone
  public let urlString: String?
  /// The task's priority, which tints its circle as the app's rows do; nil
  /// draws the quiet low-priority tint.
  public let priority: LorvexTask.Priority?

  public init(
    id: String, title: String, metadata: String?, tone: Tone = .plain, urlString: String? = nil,
    priority: LorvexTask.Priority? = nil
  ) {
    self.id = id
    self.title = title
    self.metadata = metadata
    self.tone = tone
    self.urlString = urlString
    self.priority = priority
  }
}

public struct WidgetRenderModel: Equatable, Sendable {
  public let family: WidgetFamilyKind
  public let state: WidgetRenderState
  /// The inline family's lead title, else the name of the list a configured
  /// widget shows, else "Today".
  public let headline: String
  /// Copy for a state without a lead: the empty day, stale data, or data that
  /// could not load.
  public let subheadline: String
  /// The day's briefing, when the snapshot carries one.
  public let briefing: String?
  public let statusText: String
  public let staleAgeLabel: String?
  /// Tasks completed today across the workspace.
  public let completedCount: Int
  /// The lead task, or nil when no task leads (``TodayLead``): nothing is
  /// left today, or no time runs, nothing is started, and no time is ahead.
  public let lead: WidgetLeadRender?
  /// The tasks after `lead` in Today's order, capped at the family's row budget;
  /// Today's list from its top when no task leads.
  public let taskRows: [WidgetTaskRenderRow]
  /// Every task after `lead`, uncapped, so a family without rows can still say
  /// "2 more today".
  public let upcomingCount: Int
  /// How many tasks are left ("4 left today"), for a family that has tasks
  /// left but no lead to show.
  public let dayLeft: String?
  /// The work those tasks hold ("about 3 hr"), when any carries an estimate or
  /// a time.
  public let dayWork: String?
  public let urlString: String?

  public init(
    family: WidgetFamilyKind,
    state: WidgetRenderState,
    headline: String,
    subheadline: String,
    briefing: String? = nil,
    statusText: String,
    staleAgeLabel: String? = nil,
    completedCount: Int = 0,
    lead: WidgetLeadRender? = nil,
    taskRows: [WidgetTaskRenderRow] = [],
    upcomingCount: Int = 0,
    dayLeft: String? = nil,
    dayWork: String? = nil,
    urlString: String? = nil
  ) {
    self.family = family
    self.state = state
    self.headline = headline
    self.subheadline = subheadline
    self.briefing = briefing
    self.statusText = statusText
    self.staleAgeLabel = staleAgeLabel
    self.completedCount = max(0, completedCount)
    self.lead = lead
    self.taskRows = taskRows
    self.upcomingCount = max(0, upcomingCount)
    self.dayLeft = dayLeft
    self.dayWork = dayWork
    self.urlString = urlString
  }

  /// What is left of the day on one line: ``dayLeft``, then ``dayWork``.
  public var dayLine: String? {
    guard let dayLeft else { return nil }
    return [dayLeft, dayWork].compactMap { $0 }.joined(separator: " · ")
  }

  /// How many tasks are left without naming the day ("4 left"), for a family
  /// that draws it under its "Today" title; nil when nothing is left.
  public var dayLeftUnderTitle: String? {
    remainingCount > 0 ? WidgetRenderModelBuilder.dayLeftUnderTitle(remainingCount) : nil
  }

  /// ``dayLine`` under the "Today" title: ``dayLeftUnderTitle``, then
  /// ``dayWork``.
  public var dayLineUnderTitle: String? {
    guard let dayLeftUnderTitle else { return nil }
    return [dayLeftUnderTitle, dayWork].compactMap { $0 }.joined(separator: " · ")
  }

  /// What is left of the day for a one-line slot with no "Today" title, from
  /// the whole line to the shortest, so the slot shows the first that fits:
  /// ``dayLine`` ("4 left today · about 3 hr"); the same without naming the
  /// day ("4 left · about 3 hr"), which a glance at today's work implies; the
  /// count with the day ("4 left today"); and the count alone ("4 left").
  /// Repeats are dropped, and the list is empty when nothing is left.
  public var dayLineChoices: [String] {
    var choices: [String] = []
    for choice in [dayLine, dayLineUnderTitle, dayLeft, dayLeftUnderTitle] {
      if let choice, !choices.contains(choice) { choices.append(choice) }
    }
    return choices
  }

  /// The lead and everything after it.
  public var remainingCount: Int { (lead == nil ? 0 : 1) + upcomingCount }
}

/// What a circular glance says: a Lock Screen widget or a watch complication.
public enum WidgetCircularContent: Equatable, Sendable {
  /// The snapshot could not be read. Never drawn as a reassuring checkmark.
  case unavailable
  /// Nothing is left today.
  case empty
  /// The lead task's time is running with this many minutes left.
  case running(minutesLeft: Int)
  /// No time is running: this many tasks are left today.
  case remaining(Int)
}

extension WidgetRenderModel {
  /// The circular families' content: the running lead's minutes left, else
  /// how many tasks are left, else a checkmark or the unavailable glyph.
  public var circularContent: WidgetCircularContent {
    if state == .fallback { return .unavailable }
    guard remainingCount > 0 else { return .empty }
    if let lead, lead.isRunning, let left = lead.minutesLeft {
      return .running(minutesLeft: left)
    }
    return .remaining(remainingCount)
  }
}
