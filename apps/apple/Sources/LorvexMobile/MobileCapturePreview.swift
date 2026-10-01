import LorvexCore
import SwiftUI

/// One detail the capture sheet recognized in a typed line, in the words the
/// task's sentence uses ("Tomorrow", "20 min", "Offsite 2026").
struct MobileCapturePreviewWord: Identifiable, Equatable {
  enum Role: Equatable { case plan, due, urgent, plain }

  let id: String
  let label: String
  let role: Role

  var tint: Color {
    switch role {
    case .plan: LorvexDesign.Palette.accent
    case .due: LorvexDesign.Palette.dueSoon
    case .urgent: LorvexDesign.Palette.overdue
    case .plain: LorvexDesign.Palette.neutral
    }
  }
}

/// What one capture line will create: the title left once the details are read
/// out, and the details as words. Empty when the line carries no details.
struct MobileCapturePreview: Equatable {
  let title: String
  let words: [MobileCapturePreviewWord]

  static let empty = MobileCapturePreview(title: "", words: [])
}

extension MobileStore {
  /// Read one capture line against the user's lists and the logical today.
  func captureParse(_ text: String) -> LorvexCaptureParse {
    LorvexCaptureParser.parse(
      text,
      lists: (lists?.lists ?? []).map(LorvexCaptureParser.ListOption.init(list:)),
      todayWeekday: logicalTodayWeekday,
      today: logicalTodayString)
  }

  /// The logical today's weekday, 1 = Sunday … 7 = Saturday, read from the
  /// logical day string in UTC so the device zone cannot shift it.
  var logicalTodayWeekday: Int {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: logicalTodayString) else { return 1 }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar.component(.weekday, from: date)
  }

  /// A storage-frame day `offset` days after the logical today.
  func captureStorageDate(daysFromLogicalToday offset: Int) throws -> Date {
    guard let date = PlannedDayBridge.storageDate(forLogicalDay: logicalTodayString, addingDays: offset)
    else {
      throw LorvexCoreError.unsupportedOperation("Couldn't compute a date from the configured logical day.")
    }
    return date
  }

  /// The task a capture line creates. Recognized details become fields and
  /// leave the title; the typed line is kept as the raw input when it carried
  /// any. A line with no day stays undated, so capture keeps landing in the
  /// inbox rather than on today; a line with only a clock time is planned for
  /// today at that time.
  func captureTaskDraft(line: String, notes: String) throws -> TaskCreateDraft {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let parse = captureParse(trimmed)
    var draft = TaskCreateDraft(title: parse.title, notes: notes)
    draft.listID = parse.listID
    draft.priority = parse.priority ?? draft.priority
    draft.estimatedMinutes = parse.estimatedMinutes
    draft.tags = parse.tags.isEmpty ? nil : parse.tags
    draft.rawInput = parse.hasDetails ? trimmed : nil
    if let offset = parse.resolvedPlannedDayOffset {
      draft.plannedDate = try captureStorageDate(daysFromLogicalToday: offset)
    }
    draft.plannedTime = parse.plannedTime
    if let offset = parse.resolvedDueDayOffset {
      draft.dueDate = try captureStorageDate(daysFromLogicalToday: offset)
    }
    draft.recurrence = parse.recurrence
    return draft
  }

  /// The preview the capture sheet shows under the title while the user types.
  func capturePreview(_ text: String) -> MobileCapturePreview {
    let parse = captureParse(text)
    guard parse.hasDetails else { return .empty }
    var words: [MobileCapturePreviewWord] = []
    if let offset = parse.resolvedPlannedDayOffset {
      words.append(.init(id: "when", label: captureDayLabel(offset, position: .leading), role: .plan))
    }
    // A time shows as its span, which already says the length.
    if let time = parse.plannedTime {
      words.append(
        .init(
          id: "time", label: lorvexClockRangeLabel(startMinutes: time.lowerBound, endMinutes: time.upperBound),
          role: .plan))
    } else if let minutes = parse.estimatedMinutes {
      words.append(.init(id: "length", label: MobileTodayCalmCopy.duration(minutes), role: .plan))
    }
    if let rule = parse.recurrence {
      words.append(.init(id: "repeats", label: rule.mobileLocalizedCadence, role: .plan))
    }
    if let offset = parse.resolvedDueDayOffset {
      words.append(
        .init(id: "due", label: MobileCaptureCopy.due(captureDayLabel(offset, position: .inline)), role: .due))
    }
    if let listName = parse.listName {
      words.append(.init(id: "list", label: listName, role: .plain))
    }
    if let priority = parse.priority {
      words.append(
        .init(
          id: "priority", label: MobileCaptureCopy.priority(priority),
          role: priority == .p1 ? .urgent : .plain))
    }
    for tag in parse.tags {
      words.append(.init(id: "tag.\(tag)", label: "#\(tag)", role: .plain))
    }
    return MobileCapturePreview(title: parse.title, words: words)
  }

  /// A parsed day named by ``LorvexDayPhrase`` in the storage frame the task
  /// will carry: "Tomorrow" as a word of its own, "tomorrow" after "Due".
  private func captureDayLabel(_ offset: Int, position: LorvexDayPhrase.Position) -> String {
    guard let date = try? captureStorageDate(daysFromLogicalToday: offset) else { return "" }
    return LorvexDayPhrase.phrase(
      for: date, logicalDay: logicalTodayString, position: position, locale: MobileL10n.locale)
  }
}

/// The line under the capture title: "Adds “Call the caterer”" and the
/// recognized details as tinted words, so the user sees what Add will create.
struct MobileCapturePreviewLine: View {
  let preview: MobileCapturePreview

  var body: some View {
    LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs, fillsWidth: true) {
      Text(MobileCaptureCopy.adds(preview.title))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      ForEach(preview.words) { word in
        Text(word.label)
          .font(LorvexDesign.Typography.secondaryText.weight(.medium))
          .foregroundStyle(word.tint)
          .fixedSize()
          .padding(.horizontal, LorvexDesign.Spacing.sm)
          .padding(.vertical, LorvexDesign.Spacing.xxs)
          .background(
            RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
              .fill(word.tint.opacity(0.12)))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mobileCapture.preview")
  }
}

/// The capture sheet's words for recognized details, sharing the macOS keys.
enum MobileCaptureCopy {
  static func adds(_ title: String) -> String {
    String(
      localized: "quick_add.preview.adds", defaultValue: "Adds “\(title)”", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static func due(_ day: String) -> String {
    String(
      localized: "task_detail.sentence.due_lead", defaultValue: "Due ", table: "Localizable",
      bundle: MobileL10n.bundle) + day
  }

  static func priority(_ priority: LorvexTask.Priority) -> String {
    switch priority {
    case .p1:
      String(
        localized: "task_detail.sentence.priority_phrase.high", defaultValue: "High priority",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .p2:
      String(
        localized: "task_detail.sentence.priority_phrase.normal", defaultValue: "Normal priority",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .p3:
      String(
        localized: "task_detail.sentence.priority_phrase.low", defaultValue: "Low priority",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  static var today: String {
    String(
      localized: "date.relative.today", defaultValue: "Today", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var tomorrow: String {
    String(
      localized: "date.relative.tomorrow", defaultValue: "Tomorrow", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
