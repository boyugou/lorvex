import Foundation
import SwiftUI

/// A dated excerpt travels in ordinary task notes, including through sync and export.
struct ReviewBlocker: Identifiable, Hashable {
  let day: String
  let index: Int
  let text: String
  var id: Self { self }

  static func entries(in entry: DailyReviewEntry) -> [Self] {
    (entry.blockers ?? "").split(whereSeparator: \.isNewline)
      .compactMap { String($0).trimmedNilIfEmpty }
      .enumerated().map { Self(day: entry.date, index: $0.offset, text: $0.element) }
  }

  static func nextMonday(after logicalDay: String) -> Date? {
    guard let day = PlannedDayBridge.storageDate(forLogicalDay: logicalDay) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    var monday = DateComponents()
    monday.weekday = 2
    return calendar.nextDate(after: day, matching: monday, matchingPolicy: .nextTime)
  }

  func draft(title: String, plannedDate: Date) -> TaskCreateDraft? {
    guard let title = title.trimmedNilIfEmpty else { return nil }
    let source = "\(WeekJournalCopy.blockers) · \(day)"
    return TaskCreateDraft(title: title, notes: "\(source)\n\(text)",
      plannedDate: PlannedDayBridge.storageDate(forLocalInstant: plannedDate, timeZone: .gmt))
  }
}

enum WeekJournalScope: CaseIterable {
  case all, wins, blockers, learnings

  var title: String {
    switch self {
    case .all: String(localized: "tasks.scope.all", defaultValue: "All", bundle: CoreL10n.bundle)
    case .wins: WeekJournalCopy.wins
    case .blockers: WeekJournalCopy.blockers
    case .learnings: WeekJournalCopy.learnings
    }
  }

  func includes(_ entry: DailyReviewEntry) -> Bool {
    switch self {
    case .all: true
    case .wins: entry.wins.trimmedNilIfEmpty != nil
    case .blockers: entry.blockers.trimmedNilIfEmpty != nil
    case .learnings: entry.learnings.trimmedNilIfEmpty != nil
    }
  }
}

enum WeekJournalCopy {
  static var journal: String {
    String(localized: "review.week.journal", defaultValue: "Weekly journal", bundle: CoreL10n.bundle)
  }
  static var plan: String {
    String(localized: "review.week.plan_step", defaultValue: "Plan a next step", bundle: CoreL10n.bundle)
  }
  static var wins: String {
    String(localized: "review.field.wins", defaultValue: "Wins", bundle: CoreL10n.bundle)
  }
  static var blockers: String {
    String(localized: "review.field.blockers", defaultValue: "Blockers", bundle: CoreL10n.bundle)
  }
  static var learnings: String {
    String(localized: "review.field.learnings", defaultValue: "Learnings", bundle: CoreL10n.bundle)
  }
  static var addTask: String {
    String(localized: "review.week.add_task", defaultValue: "Add a task", bundle: CoreL10n.bundle)
  }
  static var taskTitle: String {
    String(localized: "capture.title.a11y", defaultValue: "Task title", bundle: CoreL10n.bundle)
  }
  static var plannedDate: String {
    String(localized: "task_edit.planned_date", defaultValue: "Planned Date", bundle: CoreL10n.bundle)
  }
  static var openTask: String {
    String(localized: "calendar.task.open", defaultValue: "Open Task", bundle: CoreL10n.bundle)
  }
  static func mood(_ level: Int) -> String {
    String(localized: "review.calm.feel.dot", defaultValue: "Feeling \(level) of 5", bundle: CoreL10n.bundle)
  }
  static func energy(_ level: Int) -> String {
    String(localized: "review.calm.energy.dot", defaultValue: "Energy \(level) of 5", bundle: CoreL10n.bundle)
  }
}

#if os(macOS) || os(iOS)
struct ReviewFollowUpSheet: View {
  let blocker: ReviewBlocker
  let dayLabel: String
  let create: (TaskCreateDraft) async throws -> LorvexTask
  let didCreate: (LorvexTask) -> Void

  @State var plannedDate: Date
  @State private var title = ""
  @State private var saving = false
  @State private var failure: String?
  @FocusState private var editing: Bool
  @Environment(\.dismiss) private var dismiss

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    #if os(macOS)
      editor.frame(width: 390)
    #else
      ScrollView { editor }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      Text(WeekJournalCopy.plan).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(dayLabel).font(.subheadline).foregroundStyle(.secondary)
        #if os(macOS)
          ScrollView {
            Text(userContent: blocker.text)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 100)
          .fixedSize(horizontal: false, vertical: true)
        #else
          Text(userContent: blocker.text)
            .lineLimitUnlessAccessibilitySize(4)
        #endif
      }
      TextField(WeekJournalCopy.taskTitle, text: $title, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...3)
        .focused($editing)
        .accessibilityIdentifier("review.followup.title")
      DatePicker(WeekJournalCopy.plannedDate, selection: $plannedDate, displayedComponents: .date)
        .environment(\.timeZone, .gmt)
        .accessibilityIdentifier("review.followup.date")
      if let failure {
        Text(failure).foregroundStyle(.secondary).accessibilityIdentifier("review.followup.error")
      }
      HStack {
        Spacer()
        Button(ReviewPlanCopy.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button(WeekJournalCopy.addTask, action: submit)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(title.trimmedNilIfEmpty == nil)
          .accessibilityIdentifier("review.followup.save")
      }
    }
    .padding(LorvexDesign.Spacing.l)
    .disabled(saving)
    .interactiveDismissDisabled(saving)
    .onAppear { editing = true }
  }

  private func submit() {
    guard !saving, let draft = blocker.draft(title: title, plannedDate: plannedDate) else { return }
    saving = true
    failure = nil
    Task {
      do {
        let task = try await create(draft)
        didCreate(task)
        dismiss()
      } catch {
        failure = UserFacingError.message(for: UserFacingError.classify(error), copy: .standard)
        saving = false
      }
    }
  }
}
#endif
