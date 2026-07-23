import LorvexCore
import SwiftUI

struct MobileChecklistComposerRow: View {
  @State private var text = ""

  let addChecklistItem: (String) async -> Void

  var body: some View {
    HStack {
      TextField(
        String(
          localized: "checklist.add_placeholder", defaultValue: "Add checklist item",
          table: "Localizable", bundle: MobileL10n.bundle), text: $text
      )
      .textFieldStyle(.roundedBorder)
      Button {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = ""
        Task { await addChecklistItem(trimmed) }
      } label: {
        Label(
          String(
            localized: "common.add", defaultValue: "Add", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus.circle.fill")
      }
      .labelStyle(.iconOnly)
      .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }
}

/// Composes a new reminder for a task. Quick preset chips compute a common
/// relative reminder `Date` and feed it through the same binding as the custom
/// absolute `DatePicker`, so the persisted value contract — a single `Date`
/// passed to `addReminder` — is identical regardless of how it was chosen.
///
/// "In 1 hour" is an absolute elapsed-time preset. Evening and tomorrow are
/// wall-clock presets in Lorvex's synced product timezone, so travel or a
/// device-zone mismatch never changes the time another device will display.
/// A task deadline is a civil `YYYY-MM-DD` with no due-time component, so a
/// "before due" preset would invent an instant and is intentionally absent.
struct MobileReminderComposerRow: View {
  let timeZone: TimeZone
  let addReminder: (Date) async -> Void

  @State private var date: Date
  @State private var selectedPreset: ReminderPreset.ID?

  init(timeZone: TimeZone, addReminder: @escaping (Date) async -> Void) {
    self.timeZone = timeZone
    self.addReminder = addReminder
    _date = State(initialValue: TaskReminderDateTime.defaultDate(timeZone: timeZone))
  }

  private enum ReminderPreset: Identifiable {
    case inOneHour
    case thisEvening
    case tomorrowMorning

    var id: Self { self }

    var title: String {
      switch self {
      case .inOneHour:
        return String(
          localized: "reminder.preset.in_1_hour", defaultValue: "In 1 hour", table: "Localizable",
          bundle: MobileL10n.bundle)
      case .thisEvening:
        return String(
          localized: "reminder.preset.this_evening", defaultValue: "This evening",
          table: "Localizable", bundle: MobileL10n.bundle)
      case .tomorrowMorning:
        return String(
          localized: "reminder.preset.tomorrow_9am", defaultValue: "Tomorrow 9am",
          table: "Localizable", bundle: MobileL10n.bundle)
      }
    }

    var systemImage: String {
      switch self {
      case .inOneHour: return "clock"
      case .thisEvening: return "sunset"
      case .tomorrowMorning: return "sunrise"
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      let presets = availablePresets(now: Date())
      if !presets.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(presets, id: \.preset.id) { entry in
              MobileReminderPresetChip(
                title: entry.preset.title,
                systemImage: entry.preset.systemImage,
                isSelected: selectedPreset == entry.preset.id
              ) {
                selectedPreset = entry.preset.id
                if date != entry.date {
                  isApplyingPreset = true
                  date = entry.date
                }
              }
            }
          }
          .padding(.vertical, 2)
        }
      }

      HStack {
        DatePicker(
          String(
            localized: "reminder.new", defaultValue: "New Reminder", table: "Localizable",
            bundle: MobileL10n.bundle),
          selection: $date,
          displayedComponents: [.date, .hourAndMinute]
        )
        .environment(\.timeZone, timeZone)
        .onChange(of: date) { _, _ in
          // A manual picker edit clears the preset selection; a preset tap also
          // changes `date`, so it sets `isApplyingPreset` first and this handler
          // consumes that flag instead of treating it as a manual edit.
          if isApplyingPreset {
            isApplyingPreset = false
          } else {
            selectedPreset = nil
          }
        }
        Button {
          let selectedDate = date
          Task { await addReminder(selectedDate) }
        } label: {
          Label(
            String(
              localized: "common.add", defaultValue: "Add", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "plus.circle.fill")
        }
        .labelStyle(.iconOnly)
      }
    }
    .onChange(of: timeZone.identifier) { _, _ in
      selectedPreset = nil
      date = TaskReminderDateTime.defaultDate(timeZone: timeZone)
    }
  }

  /// Set while a chip tap mutates `date`, so the `DatePicker.onChange` handler
  /// does not treat that programmatic change as a manual edit that would clear
  /// the chip's selected state.
  @State private var isApplyingPreset = false

  private func availablePresets(now: Date) -> [(preset: ReminderPreset, date: Date)] {
    var entries: [(ReminderPreset, Date)] = []

    if let date = TaskReminderDateTime.presetDate(
      .inOneHour,
      now: now,
      timeZone: timeZone)
    {
      entries.append((.inOneHour, date))
    }

    if let evening = TaskReminderDateTime.presetDate(
      .thisEvening,
      now: now,
      timeZone: timeZone)
    {
      entries.append((.thisEvening, evening))
    }

    if let morning = TaskReminderDateTime.presetDate(
      .tomorrowMorning,
      now: now,
      timeZone: timeZone)
    {
      entries.append((.tomorrowMorning, morning))
    }

    return entries.map { (preset: $0.0, date: $0.1) }
  }
}
