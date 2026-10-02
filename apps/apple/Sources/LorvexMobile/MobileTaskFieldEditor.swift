import LorvexCore
import SwiftUI

/// The short sheet behind one word of the task's property sentence. It edits
/// only that field on a draft opened from the task and saves it with Done, so
/// changing a date never walks the user through the whole edit form. The list
/// word moves the task at once instead, because a list is a place, not a draft
/// field. The repeat word opens the recurrence editor
/// (`MobileStoreRecurrenceEditor`) rather than this sheet. "+ Waits on" opens
/// the dependency field, whose picker searches the tasks this one can wait on.
struct MobileTaskFieldEditor: View {
  let field: MobileTaskField
  @Binding var draft: MobileTaskEditDraft
  let lists: [LorvexList]
  let currentListID: LorvexList.ID?
  let tagSuggestions: [String]
  let searchDependencyCandidates: (String, Set<LorvexTask.ID>) async -> [LorvexTask]
  let resolveDependencyTasks: ([LorvexTask.ID]) async -> [LorvexTask]
  let isSaving: Bool
  let save: () async -> Void
  let moveToList: (LorvexList.ID) async -> Void
  let cancel: () -> Void

  /// A tag typed into the tag field but not yet added with Return.
  @State private var pendingTag = ""

  var body: some View {
    NavigationStack {
      Form {
        switch field {
        case .doOn:
          dayEditor(has: $draft.hasPlannedDate, date: $draft.plannedDate, hint: MobileTaskFieldCopy.doOnHint)
          if draft.hasPlannedDate {
            Section {
              MobileTaskTimeRows(
                time: $draft.plannedTime, day: draft.plannedDate,
                length: draft.parsedEstimatedMinutes)
            }
          }
        case .due:
          dayEditor(has: $draft.hasDueDate, date: $draft.dueDate, hint: MobileTaskFieldCopy.dueHint)
        case .hideUntil:
          dayEditor(has: $draft.hasAvailableFrom, date: $draft.availableFrom, hint: MobileTaskFieldCopy.hideHint)
        case .estimate:
          MobileTaskLengthEditor(minutesText: $draft.estimatedMinutesText)
        case .priority:
          priorityEditor
        case .list:
          listEditor
        case .tags:
          Section {
            MobileTagTokenField(tags: $draft.tags, suggestions: tagSuggestions, entry: $pendingTag)
          }
        case .waitsOn:
          Section {
            MobileDependencyField(
              dependencyIDs: $draft.dependencyIDs,
              ownTaskID: draft.id,
              searchCandidates: searchDependencyCandidates,
              resolveTitles: resolveDependencyTasks)
          } footer: {
            Text(MobileTaskFieldCopy.waitsOnHint)
          }
        case .recurrence:
          EmptyView()
        }
      }
      .navigationTitle(MobileTaskFieldCopy.title(field))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(MobileTaskFieldCopy.cancel, action: cancel)
        }
        if field != .list {
          ToolbarItem(placement: .confirmationAction) {
            Button(MobileTaskFieldCopy.done) { Task { await commitPendingTagAndSave() } }
              .disabled(isSaving || !draft.canSave)
              .accessibilityIdentifier("task.field.done")
          }
        }
      }
    }
    .presentationDetents(field == .doOn || field == .due || field == .hideUntil ? [.large] : [.medium, .large])
    .presentationDragIndicator(.visible)
  }

  /// Saves with any tag typed but not yet added, so tapping Done before
  /// Return keeps it.
  private func commitPendingTagAndSave() async {
    if !pendingTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      draft.tags = MobileTagTokenField.merging(pendingTag, into: draft.tags)
      pendingTag = ""
    }
    await save()
  }

  private func dayEditor(has: Binding<Bool>, date: Binding<Date>, hint: String) -> some View {
    let calendar = Calendar.autoupdatingCurrent
    let quick: [(String, Date)] = LorvexTaskFieldChoices.quickDays(calendar: calendar).map { offset, day in
      let label =
        offset == 0 ? MobileCaptureCopy.today
        : offset == 1 ? MobileCaptureCopy.tomorrow : day.formatted(.dateTime.weekday(.wide))
      return (label, day)
    }
    return Section {
      HStack(spacing: LorvexDesign.Spacing.s) {
        ForEach(quick, id: \.1) { label, day in
          let isOn = has.wrappedValue && calendar.isDate(date.wrappedValue, inSameDayAs: day)
          Button(label) {
            has.wrappedValue = true
            date.wrappedValue = day
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .tint(isOn ? LorvexDesign.Palette.accent : .secondary)
        }
      }
      DatePicker(
        MobileTaskFieldCopy.title(field),
        selection: Binding(
          get: { date.wrappedValue },
          set: {
            has.wrappedValue = true
            date.wrappedValue = calendar.startOfDay(for: $0)
          }),
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .labelsHidden()
      if has.wrappedValue {
        Button(MobileTaskFieldCopy.noDate, role: .destructive) { has.wrappedValue = false }
          .mobileDestructiveRowStyle()
      }
    } footer: {
      Text(hint)
    }
  }

  private var priorityEditor: some View {
    Picker(MobileTaskFieldCopy.title(field), selection: $draft.priority) {
      ForEach([LorvexTask.Priority.p1, .p2, .p3], id: \.self) { priority in
        Label(priority.localizedPhrase, systemImage: priority.prioritySymbolName)
          .tag(priority)
      }
    }
    .pickerStyle(.inline)
    .labelsHidden()
  }

  private var listEditor: some View {
    Section {
      ForEach(lists) { list in
        Button {
          Task { await moveToList(list.id) }
        } label: {
          HStack {
            Text(list.displayName).foregroundStyle(Color.primary)
            Spacer()
            if list.id == currentListID {
              Image(systemName: "checkmark").foregroundStyle(LorvexDesign.Palette.accent)
            }
          }
        }
        .disabled(isSaving)
      }
    }
  }
}

/// A task's optional time on its planned day, as form rows: its start and
/// end with a way to remove it, or one row that adds a time. Moving the start
/// keeps the length, the way a calendar event moves; an end at or before the
/// start becomes fifteen minutes after it (``LorvexTaskFieldChoices``).
struct MobileTaskTimeRows: View {
  @Binding var time: Range<Int>?
  /// The planned day at local midnight.
  let day: Date
  /// How long a new time runs: the task's estimate when it has one.
  let length: Int?

  private var calendar: Calendar { .autoupdatingCurrent }

  var body: some View {
    if let value = time {
      clockPicker(MobileTaskFieldCopy.startTime, minutes: value.lowerBound) { start in
        time = LorvexTaskFieldChoices.time(value, movingStartTo: start)
      }
      .accessibilityIdentifier("task.field.time.start")
      clockPicker(MobileTaskFieldCopy.endTime, minutes: value.upperBound) { end in
        time = LorvexTaskFieldChoices.time(value, settingEndTo: end)
      }
      .accessibilityIdentifier("task.field.time.end")
      Button(MobileTaskFieldCopy.removeTime, role: .destructive) {
        withAnimation(.snappy) { time = nil }
      }
      .mobileDestructiveRowStyle()
      .accessibilityIdentifier("task.field.time.remove")
    } else {
      Button {
        let now = calendar.dateComponents([.hour, .minute], from: .now)
        withAnimation(.snappy) {
          time = LorvexTaskFieldChoices.newTime(
            length: length, nowMinutes: (now.hour ?? 0) * 60 + (now.minute ?? 0),
            isToday: calendar.isDateInToday(day))
        }
      } label: {
        Label(MobileTaskFieldCopy.addTime, systemImage: "clock")
      }
      .accessibilityIdentifier("task.field.time.add")
    }
  }

  /// An hour-and-minute picker for `minutes` since midnight on ``day``.
  private func clockPicker(
    _ title: String, minutes: Int, onSet: @escaping (Int) -> Void
  ) -> some View {
    let midnight = calendar.startOfDay(for: day)
    return DatePicker(
      title,
      selection: Binding(
        get: {
          calendar.date(
            bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: midnight)
            ?? midnight
        },
        set: { date in
          let parts = calendar.dateComponents([.hour, .minute], from: date)
          onSet((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }),
      displayedComponents: .hourAndMinute)
  }
}

/// How long a task takes: a ring that fills toward two hours with the minutes
/// in its centre, fifteen-minute steps, and the common lengths as one tap.
struct MobileTaskLengthEditor: View {
  @Binding var minutesText: String
  @Environment(\.colorScheme) private var colorScheme

  private typealias Choices = LorvexTaskFieldChoices

  private var minutes: Int { Choices.minutes(fromText: minutesText) }

  private func set(_ value: Int) { minutesText = Choices.text(forMinutes: value) }

  var body: some View {
    Section {
      HStack(spacing: LorvexDesign.Spacing.xl) {
        Button { set(max(0, minutes - Choices.lengthStep)) } label: { Image(systemName: "minus").frame(width: 32, height: 32) }
          .buttonStyle(.bordered).buttonBorderShape(.circle)
        ZStack {
          Circle().stroke(
            LorvexDesign.Palette.accent.opacity(LorvexDesign.Palette.trackOpacity(for: colorScheme)), lineWidth: 7)
          LorvexProgressArc(
            fraction: Choices.lengthFraction(minutes), style: LorvexDesign.Palette.accent, lineWidth: 7)
          Text(minutes > 0 ? LorvexDurationFormat.minutes(minutes) : "–")
            .font(LorvexDesign.Typography.sectionHeader.monospacedDigit())
        }
        .frame(width: 112, height: 112)
        .animation(.snappy(duration: 0.2), value: minutes)
        Button { set(minutes + Choices.lengthStep) } label: { Image(systemName: "plus").frame(width: 32, height: 32) }
          .buttonStyle(.bordered).buttonBorderShape(.circle)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, LorvexDesign.Spacing.s)
      LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs) {
        ForEach(Choices.lengthPresets, id: \.self) { preset in
          Button(LorvexDurationFormat.minutes(preset)) { set(preset) }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(minutes == preset ? LorvexDesign.Palette.accent : .secondary)
        }
      }
      if minutes > 0 {
        Button(MobileTaskFieldCopy.noLength, role: .destructive) { set(0) }
          .mobileDestructiveRowStyle()
      }
    }
    .sensoryFeedback(.selection, trigger: minutes)
  }
}

enum MobileTaskFieldCopy {
  static func title(_ field: MobileTaskField) -> String {
    switch field {
    case .doOn: String(localized: "task_detail.picker.when", defaultValue: "When", table: "Localizable", bundle: MobileL10n.bundle)
    case .due: String(localized: "task_detail.picker.due", defaultValue: "Due", table: "Localizable", bundle: MobileL10n.bundle)
    case .hideUntil: String(localized: "task_detail.picker.hide_until", defaultValue: "Hide Until", table: "Localizable", bundle: MobileL10n.bundle)
    case .estimate: String(localized: "task_detail.picker.length", defaultValue: "How Long", table: "Localizable", bundle: MobileL10n.bundle)
    case .priority: String(localized: "task_detail.picker.priority", defaultValue: "Priority", table: "Localizable", bundle: MobileL10n.bundle)
    case .list: String(localized: "task_detail.picker.list", defaultValue: "List", table: "Localizable", bundle: MobileL10n.bundle)
    case .tags: String(localized: "task_detail.picker.tags", defaultValue: "Tags", table: "Localizable", bundle: MobileL10n.bundle)
    case .waitsOn: String(localized: "task_detail.waits_on", defaultValue: "Waits On", table: "Localizable", bundle: MobileL10n.bundle)
    case .recurrence: MobileTaskPropertyCopy.label(.recurrence)
    }
  }
  static var doOnHint: String {
    String(localized: "task_detail.picker.when.hint", defaultValue: "The day you plan to work on it.", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var dueHint: String {
    String(localized: "task_detail.picker.due.hint", defaultValue: "The day it has to be finished by.", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var waitsOnHint: String {
    String(localized: "task_detail.picker.waits_on.hint", defaultValue: "Tasks that must be finished before this one.", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var hideHint: String {
    String(localized: "task_detail.picker.hide_until.hint", defaultValue: "Kept off your days until then.", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var noDate: String {
    String(localized: "task_detail.picker.no_date", defaultValue: "No Date", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var addTime: String {
    String(localized: "task_detail.picker.add_time", defaultValue: "Add Time", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var removeTime: String {
    String(localized: "task_detail.picker.remove_time", defaultValue: "Remove Time", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var startTime: String {
    String(localized: "task_detail.picker.start_time", defaultValue: "Start Time", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var endTime: String {
    String(localized: "task_detail.picker.end_time", defaultValue: "End Time", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var noLength: String {
    String(localized: "task_detail.picker.no_length", defaultValue: "No Estimate", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var done: String {
    String(localized: "today.calm.schedule.done", defaultValue: "Done", table: "Localizable", bundle: MobileL10n.bundle)
  }
  static var cancel: String {
    String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle)
  }
}
