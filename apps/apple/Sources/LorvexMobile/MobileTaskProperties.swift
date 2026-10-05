import LorvexCore
import SwiftUI

/// A task field the iPhone task detail can open on its own.
enum MobileTaskField: String, Identifiable, CaseIterable {
  case doOn, estimate, due, list, priority
  case recurrence = "repeat"
  case tags, waitsOn, hideUntil
  var id: String { rawValue }
}

/// The task's fields as the iPhone task detail lists them, matching the macOS
/// inspector: one row per set field, in the order a person plans a task (when
/// and for how long, the deadline, where it belongs and how urgent it is, then
/// how it repeats, is tagged, and hides), and the unset fields in the same
/// order for the Add menu. Days are named by the same rules
/// (``LorvexDayPhrase``), each naming its own day, since a row stands alone
/// and has no planned day before it to say "the same day" about. A hide-until day that has arrived hides
/// nothing, so it is offered again instead of listed. The tasks a task waits
/// on have their own section, so Waits on is only ever an addition.
struct MobileTaskProperties: Equatable {
  struct Row: Identifiable, Equatable {
    let field: MobileTaskField
    /// The value as plain text, which is also what leaves the app in shared text.
    let value: String
    /// The parts of a value that is a list (a task's tags); nil for a value
    /// that is one phrase.
    var items: [String]? = nil
    var tint: Tint?
    var id: String { field.rawValue }

    /// The value as the detail draws it. A list's parts stay whole and each
    /// dot stays with the part before it, so a row that wraps breaks after a
    /// dot and never starts a line with one.
    var displayValue: String {
      items.map { lorvexDotJoined($0.map(lorvexUnbreakable)) } ?? value
    }
  }

  enum Tint: Equatable { case overdue, soon, high }

  /// How the rows name a day.
  enum DayStyle: Equatable {
    /// Relative to today, as the detail shows it: "Tomorrow", "Sep 20 · 9
    /// days late".
    case relative
    /// A date that stays true after today, for text that leaves the app:
    /// "Tue, Sep 29, 2026".
    case dated
  }

  var rows: [Row]
  var additions: [MobileTaskField]

  /// - Parameters:
  ///   - listName: the task's list name, or `nil` when it has none.
  ///   - logicalDay: the product's logical today, `yyyy-MM-dd`.
  ///   - days: how the rows name a day.
  init(task: LorvexTask, listName: String?, logicalDay: String, days: DayStyle = .relative) {
    typealias Copy = MobileTaskPropertyCopy
    var rows: [Row] = []
    var additions: [MobileTaskField] = []
    func field(_ field: MobileTaskField, _ value: String?, items: [String]? = nil, tint: Tint? = nil) {
      if let value {
        rows.append(Row(field: field, value: value, items: items, tint: tint))
      } else {
        additions.append(field)
      }
    }
    // A planned day after a deadline that has not passed yet says so in the
    // detail; text that leaves the app keeps only its dates, which stay true.
    let isAfterDeadline =
      days == .relative
      && LorvexDayPhrase.isPlannedAfterDeadline(planned: task.plannedDate, due: task.dueDate, logicalDay: logicalDay)
    field(
      .doOn,
      task.plannedDate.map { planned in
        let day =
          days == .dated
          ? Self.dated(planned) : LorvexDayPhrase.phrase(for: planned, logicalDay: logicalDay, position: .leading)
        let when = task.plannedTime.map { Copy.day(day, at: $0) } ?? day
        return isAfterDeadline ? LorvexDayPhrase.afterDeadline(when) : when
      },
      tint: isAfterDeadline ? .soon : nil)
    field(.estimate, task.estimatedMinutes.flatMap { $0 > 0 ? LorvexDurationFormat.minutes($0) : nil })
    if let due = task.dueDate {
      let offset = lorvexDayOffset(from: logicalDay, to: due)
      let tint: Tint? = offset.map { $0 < 0 ? .overdue : ($0 <= 1 ? .soon : nil) } ?? nil
      let day =
        days == .dated
        ? Self.dated(due) : Self.sentenceCased(LorvexDayPhrase.due(due, plannedDay: nil, logicalDay: logicalDay))
      field(.due, day, tint: tint)
    } else {
      field(.due, nil)
    }
    field(.list, listName)
    field(
      .priority, task.priority == .p2 ? nil : task.priority.localizedName,
      tint: task.priority == .p1 ? .high : nil)
    field(.recurrence, task.recurrence?.localizedCadence(anchorDay: task.recurrenceAnchorDay(logicalDay: logicalDay)))
    field(.tags, task.tags.isEmpty ? nil : task.tags.joined(separator: " · "), items: task.tags)
    if task.dependsOn.isEmpty { additions.append(.waitsOn) }
    let hiddenUntil = task.availableFrom.flatMap {
      (lorvexDayOffset(from: logicalDay, to: $0) ?? 1) > 0 ? $0 : nil
    }
    field(
      .hideUntil,
      hiddenUntil.map {
        days == .dated
          ? Self.dated($0)
          : Self.sentenceCased(LorvexDayPhrase.phrase(for: $0, logicalDay: logicalDay, position: .inline))
      })
    self.rows = rows
    self.additions = additions
  }

  /// A stored day as a date with its weekday and year, in the user's language
  /// ("Tue, Sep 29, 2026", "2026年9月29日周二"). The stored day names a calendar
  /// day, so it is written in UTC and never shifts across time zones.
  static func dated(_ day: Date) -> String {
    LorvexDateFormatters.string(day, template: "yMMMEd", timeZone: .gmt)
  }

  /// A phrase written to follow other words ("the same day") as it reads
  /// standing alone in a row ("The same day"), capitalized by the rules of
  /// the app's language (Turkish "i" becomes "İ"). Scripts without case are
  /// unchanged.
  static func sentenceCased(_ phrase: String, locale: Locale = LorvexClockFormat.displayLocale) -> String {
    guard let first = phrase.first else { return phrase }
    return String(first).uppercased(with: locale) + phrase.dropFirst()
  }
}

/// The rows of ``MobileTaskProperties`` in a grouped list: each row is the
/// field's icon, its name, and its value at the trailing edge, and opens that
/// one field's editor. A last "Add Detail" row is a menu of everything the
/// task does not carry yet: the unset fields, then a checklist and a reminder
/// when the task has none, which `addChecklist` and `addReminder` unfold.
struct MobileTaskPropertiesSection: View {
  let properties: MobileTaskProperties
  let edit: (MobileTaskField) -> Void
  var addChecklist: (() -> Void)?
  var addReminder: (() -> Void)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// The icon column grows with the text so a large glyph never runs into
  /// the field name beside it.
  @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

  var body: some View {
    Section {
      ForEach(properties.rows) { row in
        Button { edit(row.field) } label: { rowLabel(row) }
          .buttonStyle(.plain)
          .accessibilityIdentifier("task.detail.row.\(row.id)")
      }
      if !properties.additions.isEmpty || addChecklist != nil || addReminder != nil {
        addMenu
      }
    }
  }

  private func rowLabel(_ row: MobileTaskProperties.Row) -> some View {
    let tint = color(row.tint)
    let icon = Image(systemName: MobileTaskPropertyCopy.systemImage(row.field))
      .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
      .frame(width: iconWidth)
      .accessibilityHidden(true)
    let name = Text(MobileTaskPropertyCopy.label(row.field)).foregroundStyle(.secondary)
    let value = Text(row.displayValue)
      .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
    return Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          HStack(spacing: LorvexDesign.Spacing.s) { icon; name }
          value.fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          icon
          name.lineLimit(1).layoutPriority(1)
          Spacer(minLength: LorvexDesign.Spacing.m)
          value
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .font(LorvexDesign.Typography.primaryText)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }

  private var addMenu: some View {
    Menu {
      ForEach(properties.additions) { field in
        Button(MobileTaskPropertyCopy.label(field), systemImage: MobileTaskPropertyCopy.systemImage(field)) {
          edit(field)
        }
      }
      if addChecklist != nil || addReminder != nil {
        Divider()
      }
      if let addChecklist {
        Button(MobileTaskPropertyCopy.checklist, systemImage: "checklist", action: addChecklist)
      }
      if let addReminder {
        Button(MobileTaskPropertyCopy.reminder, systemImage: "bell", action: addReminder)
      }
    } label: {
      Label(MobileTaskPropertyCopy.addDetail, systemImage: "plus.circle.fill")
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .accessibilityIdentifier("task.detail.add")
  }

  private func color(_ tint: MobileTaskProperties.Tint?) -> Color? {
    switch tint {
    case .overdue: LorvexDesign.Palette.overdue
    case .soon: LorvexDesign.Palette.dueSoon
    case .high: LorvexDesign.Palette.priorityHigh
    case nil: nil
    }
  }
}

/// The words of the iPhone task detail's fields, sharing the macOS keys.
enum MobileTaskPropertyCopy {
  static func label(_ field: MobileTaskField) -> String {
    switch field {
    case .doOn: String(localized: "task_detail.add.when", defaultValue: "When", table: "Localizable", bundle: MobileL10n.bundle)
    case .estimate: String(localized: "task_detail.add.length", defaultValue: "How long", table: "Localizable", bundle: MobileL10n.bundle)
    case .due: String(localized: "task_detail.add.due", defaultValue: "Due", table: "Localizable", bundle: MobileL10n.bundle)
    case .list: String(localized: "task_detail.add.list", defaultValue: "List", table: "Localizable", bundle: MobileL10n.bundle)
    case .priority: String(localized: "task_detail.add.priority", defaultValue: "Priority", table: "Localizable", bundle: MobileL10n.bundle)
    case .recurrence: String(localized: "task_detail.add.repeat", defaultValue: "Repeat", table: "Localizable", bundle: MobileL10n.bundle)
    case .tags: String(localized: "task_detail.add.tag", defaultValue: "Tags", table: "Localizable", bundle: MobileL10n.bundle)
    case .waitsOn: String(localized: "task_detail.add.waits_on", defaultValue: "Waits on", table: "Localizable", bundle: MobileL10n.bundle)
    case .hideUntil: String(localized: "task_detail.add.hide_until", defaultValue: "Hide until", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// The field's icon, the same symbol the macOS inspector draws.
  static func systemImage(_ field: MobileTaskField) -> String {
    switch field {
    case .doOn: "calendar"
    case .estimate: "hourglass"
    case .due: "flag"
    case .list: "list.bullet"
    case .priority: "exclamationmark.circle"
    case .recurrence: "repeat"
    case .tags: "tag"
    case .waitsOn: "arrow.triangle.branch"
    case .hideUntil: "eye.slash"
    }
  }

  static var addDetail: String {
    String(localized: "task_detail.add.menu", defaultValue: "Add Detail", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var checklist: String {
    String(localized: "task_detail.section.checklist", defaultValue: "Checklist", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var assistantContext: String {
    String(
      localized: "task_detail.section.assistant_context", defaultValue: "Assistant Context", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
  static var reminder: String {
    String(localized: "task_detail.add.reminder", defaultValue: "Reminder", table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// A planned day with the task's time on it: "Today, 9:45 – 10:30 AM".
  static func day(_ day: String, at time: Range<Int>) -> String {
    let range = lorvexClockRangeLabel(startMinutes: time.lowerBound, endMinutes: time.upperBound)
    return String(
      localized: "task_detail.do_on.day_time", defaultValue: "\(day), \(range)",
      table: "Localizable", bundle: MobileL10n.bundle)
  }
}
