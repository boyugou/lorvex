import LorvexCore
import SwiftUI

/// One detail the quick-add row recognized in the typed line, written the way
/// the task's property sentence will show it ("Tomorrow", "20 min",
/// "Offsite 2026").
struct QuickAddPreviewWord: Identifiable, Equatable {
  enum Role: Equatable {
    /// The plan: the day it is done on and how long it takes.
    case plan
    /// A deadline.
    case due
    /// Urgent now.
    case urgent
    /// Filing: list, tags, low priority.
    case plain
  }

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

/// What a quick-add line will create: the title that remains once the details
/// are read out of it, and the details as words.
struct QuickAddPreview: Equatable {
  let title: String
  let words: [QuickAddPreviewWord]

  static let empty = QuickAddPreview(title: "", words: [])
}

extension AppStore {
  /// The preview `QuickAddRow` shows under its field while the user types.
  /// Empty when the line carries no details, so a plain title shows nothing.
  func quickAddPreview(_ text: String) -> QuickAddPreview {
    let parse = captureParse(text)
    guard parse.hasDetails else { return .empty }
    var words: [QuickAddPreviewWord] = []
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
      words.append(.init(id: "length", label: TodayCalmCopy.duration(minutes), role: .plan))
    }
    if let rule = parse.recurrence {
      words.append(.init(id: "repeats", label: lorvexRecurrenceLabel(rule), role: .plan))
    }
    if let offset = parse.resolvedDueDayOffset {
      words.append(
        .init(
          id: "due", label: TaskDetailSentenceCopy.dueLead + captureDayLabel(offset, position: .inline),
          role: .due))
    }
    if let listName = parse.listName {
      words.append(.init(id: "list", label: listName, role: .plain))
    }
    if let priority = parse.priority {
      words.append(
        .init(
          id: "priority", label: TaskDetailSentenceCopy.priorityPhrase(priority),
          role: priority == .p1 ? .urgent : .plain))
    }
    for tag in parse.tags {
      words.append(.init(id: "tag.\(tag)", label: "#\(tag)", role: .plain))
    }
    return QuickAddPreview(title: parse.title, words: words)
  }

  /// A parsed day named by ``LorvexDayPhrase`` in the storage frame the task
  /// will carry: "Tomorrow" as a word of its own, "tomorrow" after "Due".
  private func captureDayLabel(_ offset: Int, position: LorvexDayPhrase.Position) -> String {
    guard let date = try? storageDate(daysFromLogicalToday: offset) else { return "" }
    return LorvexDayPhrase.phrase(for: date, logicalDay: logicalTodayDateString, position: position)
  }
}

/// The line under the quick-add field: "Adds “Call the caterer”" followed by the
/// recognized details as tinted words, so the user sees what Return will create
/// before pressing it.
struct QuickAddPreviewLine: View {
  let preview: QuickAddPreview

  var body: some View {
    LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xxs, fillsWidth: true) {
      Text(
        String(
          localized: "quick_add.preview.adds", defaultValue: "Adds “\(preview.title)”",
          table: "Localizable", bundle: LorvexL10n.bundle)
      )
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .truncationMode(.middle)
      ForEach(preview.words) { word in
        Text(word.label)
          .font(LorvexDesign.Typography.secondaryText.weight(.medium))
          .foregroundStyle(word.tint)
          .fixedSize()
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(
            RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
              .fill(word.tint.opacity(0.1)))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("workspace.quickAdd.preview")
  }
}
