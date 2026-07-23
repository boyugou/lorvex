import Foundation
import LorvexDomain

/// The seven plain RFC 5545 weekday tokens in canonical Monday-first order.
/// Ordinal tokens such as `1MO` remain part of ``TaskRecurrenceRule`` but are
/// intentionally not projected into the basic seven-chip editor.
public enum TaskRecurrenceWeekday: String, CaseIterable, Sendable {
  case monday = "MO"
  case tuesday = "TU"
  case wednesday = "WE"
  case thursday = "TH"
  case friday = "FR"
  case saturday = "SA"
  case sunday = "SU"

  public static func orderedCodes(_ weekdays: Set<Self>) -> [String] {
    allCases.filter(weekdays.contains).map(\.rawValue)
  }
}

/// A recurrence mutation resolved at the editor boundary. `.none` is a real
/// no-op and must not enter the write funnel (which would otherwise mint a new
/// version, changelog row, outbox item, and clear recurrence exceptions).
public enum TaskRecurrenceEditorSaveIntent: Equatable, Sendable {
  case none
  case remove
  case set(TaskRecurrenceRule)
}

public enum TaskRecurrenceEditorError: Error, Equatable, Sendable {
  case invalidInterval
  case concurrentChange
}

/// Full-fidelity state for the basic Apple recurrence editors.
///
/// The UI exposes only enablement, frequency, interval, anchor, and weekly
/// weekday chips. The draft retains the complete original rule and overlays
/// only fields the user actually changed, so an interval edit never destroys
/// AI-authored `BYMONTH`, `BYSETPOS`, `WKST`, `UNTIL`, or `COUNT` values.
/// `saveIntent(liveRule:)` overlays those local changes onto the latest loaded
/// rule and rejects same-axis concurrent edits rather than silently winning.
public struct TaskRecurrenceEditorDraft: Equatable, Sendable {
  public static let maximumInterval = Int(ValidationLimits.maxRecurrenceInterval)

  public let originalRule: TaskRecurrenceRule?
  public var isEnabled: Bool
  public var frequency: TaskRecurrenceRule.Frequency
  public var intervalText: String
  public var anchor: TaskRecurrenceRule.Anchor
  public var weeklyDays: Set<TaskRecurrenceWeekday>

  public init(rule: TaskRecurrenceRule? = nil) {
    let normalized = rule?.editorCanonicalized
    originalRule = normalized
    isEnabled = normalized != nil
    frequency = normalized?.freq ?? .weekly
    intervalText = String(normalized?.interval ?? 1)
    anchor = normalized?.anchor ?? .schedule
    if normalized?.freq == .weekly, normalized?.anchor == .schedule {
      weeklyDays = Set((normalized?.byDay ?? []).compactMap(TaskRecurrenceWeekday.init(rawValue:)))
    } else {
      weeklyDays = []
    }
  }

  public var validatedInterval: Int? {
    let text = intervalText.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return 1 }
    guard let value = Int(text), value >= 1,
      value <= Self.maximumInterval
    else {
      return nil
    }
    return value
  }

  /// True for any semantic recurrence edit, and also for invalid raw interval
  /// text so reload reconciliation protects the in-progress value.
  public var hasChanges: Bool {
    if !isEnabled { return originalRule != nil }
    guard let originalRule else { return true }
    guard let interval = validatedInterval else { return true }
    return frequency != originalRule.freq
      || interval != (originalRule.interval ?? 1)
      || anchor != originalRule.anchor
      || weeklyDays != Self.editorWeekdays(in: originalRule)
  }

  public var canSave: Bool {
    isEnabled ? validatedInterval != nil && hasChanges : hasChanges
  }

  /// Stable editor-only fingerprint used to detect recurrence typing that
  /// starts while an async reload is suspended.
  public var fingerprint: String {
    [
      String(isEnabled), frequency.rawValue, intervalText, anchor.rawValue,
      TaskRecurrenceWeekday.orderedCodes(weeklyDays).joined(separator: ","),
    ].joined(separator: "\u{1F}")
  }

  /// Rebase edits made after a save began onto the rule that save actually
  /// persisted. Axes unchanged since `submitted` adopt the canonical persisted
  /// value; axes the user changed while the write was suspended remain in the
  /// draft for the next save. This prevents both lost typing and a false
  /// concurrent-change error from retaining the pre-save baseline.
  public func rebasedPreservingEdits(
    since submitted: Self,
    onto persistedRule: TaskRecurrenceRule?
  ) -> Self {
    var rebased = Self(rule: persistedRule)
    if isEnabled != submitted.isEnabled { rebased.isEnabled = isEnabled }
    if frequency != submitted.frequency { rebased.frequency = frequency }
    if intervalText != submitted.intervalText { rebased.intervalText = intervalText }
    if anchor != submitted.anchor { rebased.anchor = anchor }
    if weeklyDays != submitted.weeklyDays { rebased.weeklyDays = weeklyDays }
    return rebased
  }

  /// Resolve the local draft against the latest loaded recurrence.
  ///
  /// Hidden fields come from `liveRule`. A local frequency change clears every
  /// old frequency-coupled positional modifier; a completion anchor clears the
  /// same fields because the core rejects that combination. Termination
  /// (`UNTIL`/`COUNT`) remains intact. If both the peer and the user changed the
  /// same visible axis to different values, the save is rejected.
  public func saveIntent(liveRule: TaskRecurrenceRule?) throws
    -> TaskRecurrenceEditorSaveIntent
  {
    if !isEnabled {
      guard let live = liveRule?.editorCanonicalized else { return .none }
      guard let originalRule,
        live.isSemanticallyEquivalent(to: originalRule)
      else {
        throw TaskRecurrenceEditorError.concurrentChange
      }
      return .remove
    }
    guard let interval = validatedInterval else {
      throw TaskRecurrenceEditorError.invalidInterval
    }
    guard hasChanges else { return .none }

    guard let originalRule else {
      let proposed = Self.newRule(
        frequency: frequency, interval: interval, anchor: anchor, weekdays: weeklyDays)
        .editorCanonicalized
      if let liveRule {
        if proposed.isSemanticallyEquivalent(to: liveRule) { return .none }
        throw TaskRecurrenceEditorError.concurrentChange
      }
      return .set(proposed)
    }
    guard var live = liveRule?.editorCanonicalized else {
      throw TaskRecurrenceEditorError.concurrentChange
    }

    let frequencyChanged = frequency != originalRule.freq
    let intervalChanged = interval != (originalRule.interval ?? 1)
    let anchorChanged = anchor != originalRule.anchor
    let weekdaysChanged = weeklyDays != Self.editorWeekdays(in: originalRule)

    if frequencyChanged, live.freq != originalRule.freq, live.freq != frequency {
      throw TaskRecurrenceEditorError.concurrentChange
    }
    if intervalChanged,
      (live.interval ?? 1) != (originalRule.interval ?? 1),
      (live.interval ?? 1) != interval
    {
      throw TaskRecurrenceEditorError.concurrentChange
    }
    if anchorChanged, live.anchor != originalRule.anchor, live.anchor != anchor {
      throw TaskRecurrenceEditorError.concurrentChange
    }
    if weekdaysChanged {
      guard live.freq == originalRule.freq, live.anchor == originalRule.anchor else {
        throw TaskRecurrenceEditorError.concurrentChange
      }
      let liveDays = Self.editorWeekdays(in: live)
      let originalDays = Self.editorWeekdays(in: originalRule)
      if liveDays != originalDays, liveDays != weeklyDays {
        throw TaskRecurrenceEditorError.concurrentChange
      }
    }

    if frequencyChanged {
      live.freq = frequency
      live.clearPositionalModifiers()
    }
    if intervalChanged { live.interval = interval }
    if anchorChanged { live.anchor = anchor }

    if frequencyChanged || anchorChanged {
      if live.anchor == .schedule, live.freq == .weekly {
        live.byDay = Self.dayCodesOrNil(weeklyDays)
      }
    } else if weekdaysChanged {
      guard live.anchor == .schedule, live.freq == .weekly else {
        throw TaskRecurrenceEditorError.concurrentChange
      }
      live.byDay = Self.dayCodesOrNil(weeklyDays)
    }
    if live.anchor == .completion { live.clearPositionalModifiers() }

    let proposed = live.editorCanonicalized
    if let liveRule, proposed.isSemanticallyEquivalent(to: liveRule) { return .none }
    return .set(proposed)
  }

  private static func newRule(
    frequency: TaskRecurrenceRule.Frequency,
    interval: Int,
    anchor: TaskRecurrenceRule.Anchor,
    weekdays: Set<TaskRecurrenceWeekday>
  ) -> TaskRecurrenceRule {
    TaskRecurrenceRule(
      freq: frequency,
      interval: interval,
      byDay: anchor == .schedule && frequency == .weekly ? dayCodesOrNil(weekdays) : nil,
      anchor: anchor)
  }

  private static func editorWeekdays(in rule: TaskRecurrenceRule) -> Set<TaskRecurrenceWeekday> {
    guard rule.freq == .weekly, rule.anchor == .schedule else { return [] }
    return Set((rule.byDay ?? []).compactMap(TaskRecurrenceWeekday.init(rawValue:)))
  }

  private static func dayCodesOrNil(_ weekdays: Set<TaskRecurrenceWeekday>) -> [String]? {
    let codes = TaskRecurrenceWeekday.orderedCodes(weekdays)
    return codes.isEmpty ? nil : codes
  }
}

public extension TaskRecurrenceRule {
  /// Semantic equality through the same task recurrence normalizer every write
  /// surface uses (default interval, nil/empty modifiers, and canonical BYDAY
  /// ordering therefore compare identically).
  func isSemanticallyEquivalent(to other: TaskRecurrenceRule) -> Bool {
    editorCanonicalized == other.editorCanonicalized
  }

  fileprivate var editorCanonicalized: TaskRecurrenceRule {
    guard let raw = canonicalRecurrenceJSON() else { return self }
    switch ValidationRecurrence.normalizeTaskRecurrence(raw) {
    case .success(let canonical?):
      return TaskRecurrenceRule.bridgeRule(from: canonical) ?? self
    case .success(nil), .failure:
      return self
    }
  }

  fileprivate mutating func clearPositionalModifiers() {
    byDay = nil
    byMonth = nil
    byMonthDay = nil
    bySetPos = nil
    wkst = nil
  }
}
