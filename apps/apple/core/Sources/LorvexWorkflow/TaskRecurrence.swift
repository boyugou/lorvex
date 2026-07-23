import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Top-level `set_task_recurrence` workflow op. Canonicalizes the user's
/// recurrence rule into the stored JSON shape, normalizes it through
/// ``ValidationRecurrence/normalizeTaskRecurrence(_:)``, and delegates
/// to ``RecurrenceConfig/applyRecurrenceChange(_:taskId:recurrencePatch:duePatch:today:version:now:)``
/// for the LWW-gated UPDATE + dependent column reconciliation.
public enum TaskRecurrence {
  /// User-facing rule shape; `freq` is the only required field, all
  /// others extend the canonical RRULE form.
  public struct RuleInput: Sendable, Equatable {
    public var freq: String
    public var interval: UInt32?
    public var byday: [String]?
    public var bymonth: [Int64]?
    public var bymonthday: [Int64]
    public var bysetpos: [Int64]?
    public var wkst: String?
    public var until: String?
    public var count: UInt32?
    /// Lorvex `ANCHOR` extension: `"completion"` repeats INTERVAL units after
    /// the task is completed; `nil`/`"schedule"` is the default fixed cadence.
    public var anchor: String?

    public init(
      freq: String,
      interval: UInt32? = nil,
      byday: [String]? = nil,
      bymonth: [Int64]? = nil,
      bymonthday: [Int64] = [],
      bysetpos: [Int64]? = nil,
      wkst: String? = nil,
      until: String? = nil,
      count: UInt32? = nil,
      anchor: String? = nil
    ) {
      self.freq = freq
      self.interval = interval
      self.byday = byday
      self.bymonth = bymonth
      self.bymonthday = bymonthday
      self.bysetpos = bysetpos
      self.wkst = wkst
      self.until = until
      self.count = count
      self.anchor = anchor
    }
  }

  /// Input envelope for ``setTaskRecurrence(_:hlc:input:)``.
  public struct SetTaskRecurrenceInput: Sendable {
    public var taskId: TaskId
    public var rule: RuleInput

    public init(taskId: TaskId, rule: RuleInput) {
      self.taskId = taskId
      self.rule = rule
    }
  }

  /// Result of ``setTaskRecurrence(_:hlc:input:)``: the enriched
  /// before / after task JSON plus a human-readable summary string.
  public struct MutationResult: Sendable {
    public let taskId: String
    public let beforeTask: JSONValue
    public let afterTask: JSONValue
    public let summary: String
  }

  /// Apply the recurrence rule to the task. The caller owns the
  /// surrounding transaction (the underlying
  /// ``RecurrenceConfig/applyRecurrenceChange`` helper opens its
  /// own immediate transaction when handed a writer; this entry takes a
  /// mid-transaction `Database` and delegates to the in-tx variant).
  public static func setTaskRecurrence(
    _ db: Database,
    hlc: HlcSession,
    input: SetTaskRecurrenceInput
  ) throws -> MutationResult {
    let freqLabel = try canonicalFreq(input.rule.freq)
    let rawJSON = try ruleJSONString(input.rule)
    let normalized: String?
    switch ValidationRecurrence.normalizeTaskRecurrence(rawJSON) {
    case .success(let value): normalized = value
    case .failure(let err): throw StoreError.validation(err.description)
    }
    guard let recurrenceJSON = normalized else {
      throw StoreError.validation(
        "recurrence rule resulted in empty after normalization")
    }

    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: input.taskId)
    let title = TaskResponse.taskTitle(before)
    let now = SyncTimestampFormat.syncTimestampNow()
    let today = try WorkflowTimezone.todayYmdForConn(db)
    let version = hlc.nextVersionString()

    do {
      _ = try RecurrenceConfig.applyRecurrenceChangeInTx(
        db,
        taskId: input.taskId,
        recurrencePatch: .set(recurrenceJSON),
        dueDatePatch: .unset,
        today: today,
        version: version,
        now: now)
    } catch let error as RecurrenceConfig.ChangeError {
      throw mapChangeError(error)
    }

    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: input.taskId)
    let summary = recurrenceSummary(
      title: title, rule: input.rule, freqLabel: freqLabel)
    return MutationResult(
      taskId: input.taskId.asString,
      beforeTask: before,
      afterTask: after,
      summary: summary)
  }

  // MARK: - Helpers

  private static func canonicalFreq(_ raw: String) throws -> String {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "DAILY": return "DAILY"
    case "WEEKLY": return "WEEKLY"
    case "MONTHLY": return "MONTHLY"
    case "YEARLY": return "YEARLY"
    default:
      throw StoreError.validation(
        "freq must be one of daily, weekly, monthly, yearly")
    }
  }

  private static func ruleJSONString(_ rule: RuleInput) throws -> String {
    if let byday = rule.byday, byday.isEmpty {
      throw StoreError.validation(
        "BYDAY array must contain at least one weekday code (or be omitted)")
    }
    var obj: [String: JSONValue] = [:]
    obj["FREQ"] = .string(try canonicalFreq(rule.freq))
    if let interval = rule.interval {
      obj["INTERVAL"] = .int(Int64(interval))
    }
    if let byday = rule.byday, !byday.isEmpty {
      obj["BYDAY"] = .array(byday.map(JSONValue.string))
    }
    if let bymonth = rule.bymonth, !bymonth.isEmpty {
      obj["BYMONTH"] = .array(bymonth.map(JSONValue.int))
    }
    if !rule.bymonthday.isEmpty {
      obj["BYMONTHDAY"] = .array(rule.bymonthday.map(JSONValue.int))
    }
    if let bysetpos = rule.bysetpos, !bysetpos.isEmpty {
      obj["BYSETPOS"] = .array(bysetpos.map(JSONValue.int))
    }
    if let wkst = rule.wkst {
      obj["WKST"] = .string(wkst)
    }
    if let until = rule.until {
      obj["UNTIL"] = .string(until)
    }
    if let count = rule.count {
      obj["COUNT"] = .int(Int64(count))
    }
    if let anchor = rule.anchor, !anchor.isEmpty {
      obj["ANCHOR"] = .string(anchor)
    }
    return try canonicalizeJSON(.object(obj))
  }

  private static func recurrenceSummary(
    title: String, rule: RuleInput, freqLabel: String
  ) -> String {
    let intervalPart: String
    if let n = rule.interval, n > 1 {
      intervalPart = " every \(n)"
    } else {
      intervalPart = ""
    }
    let bydayPart: String
    if let byday = rule.byday, !byday.isEmpty {
      bydayPart = " on \(byday.joined(separator: ","))"
    } else {
      bydayPart = ""
    }
    let bymonthdayPart: String
    if !rule.bymonthday.isEmpty {
      bymonthdayPart = " on day \(rule.bymonthday.map(String.init).joined(separator: ","))"
    } else {
      bymonthdayPart = ""
    }
    let countPart: String
    if let c = rule.count {
      countPart = " for \(c) occurrences"
    } else {
      countPart = ""
    }
    let untilPart: String
    if let u = rule.until {
      untilPart = " until \(u)"
    } else {
      untilPart = ""
    }
    let anchorPart = rule.anchor == "completion" ? " after completion" : ""
    return
      "Set recurrence on '\(title)': "
      + "\(freqLabel)\(intervalPart)\(bydayPart)\(bymonthdayPart)\(countPart)\(untilPart)\(anchorPart)"
  }

  private static func mapChangeError(_ error: RecurrenceConfig.ChangeError)
    -> StoreError
  {
    switch error {
    case .clearDueDateOnRecurring:
      return .validation("recurring tasks must have a due_date")
    case .staleVersion(let taskId):
      return .staleVersion(entity: EntityName.task, id: taskId)
    }
  }
}
