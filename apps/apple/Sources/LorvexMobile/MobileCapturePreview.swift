import LorvexCore
import SwiftUI

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
  /// Empty when the line carries no details, so a plain title shows nothing.
  func capturePreview(_ text: String) -> LorvexCapturePreview {
    LorvexCapturePreview(parse: captureParse(text), logicalDay: logicalTodayString)
  }
}

/// The line under the capture title: "Adds “Call the caterer”" and the
/// recognized details as tinted words, so the user sees what Add will create.
struct MobileCapturePreviewLine: View {
  let preview: LorvexCapturePreview

  var body: some View {
    LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs, fillsWidth: true) {
      Text(preview.addsLine)
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

/// The relative day names the task field editor offers as quick choices.
enum MobileCaptureCopy {
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
