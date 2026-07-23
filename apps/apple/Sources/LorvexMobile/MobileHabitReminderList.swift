import LorvexCore
import SwiftUI

/// The habit-detail reminders block. Read-only when no editing closures are
/// supplied (renders the stored times as chips, nothing when there are none),
/// interactive when they are: each policy can be retimed, enabled/disabled, or
/// removed, and a trailing control adds a new time. Mirrors the macOS
/// habit-detail reminder editor; all mutations run through the store's
/// `upsert_habit_reminder_policy` / `delete_habit_reminder_policy` paths.
struct MobileHabitReminderList: View {
  let policies: [HabitReminderPolicy]
  let isMutating: Bool
  var addReminder: ((String) async -> Void)? = nil
  var setReminderTime: ((HabitReminderPolicy, String) async -> Void)? = nil
  var toggleReminder: ((HabitReminderPolicy) async -> Void)? = nil
  var removeReminder: ((HabitReminderPolicy) async -> Void)? = nil

  @State private var timeSheet: MobileHabitReminderTimeContext?

  private var isInteractive: Bool { addReminder != nil }
  private var sortedPolicies: [HabitReminderPolicy] {
    policies.sorted { $0.reminderTime < $1.reminderTime }
  }

  var body: some View {
    if !policies.isEmpty || isInteractive {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        Label(String(localized: "habits.detail.reminders", defaultValue: "Reminders", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "bell")
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)

        if sortedPolicies.isEmpty {
          Text(String(localized: "habits.reminders.empty", defaultValue: "No reminders yet.", table: "Localizable", bundle: MobileL10n.bundle))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
        } else {
          ForEach(sortedPolicies) { policy in
            reminderRow(policy)
          }
        }

        if isInteractive {
          Button {
            timeSheet = MobileHabitReminderTimeContext(
              policy: nil, time: MobileHabitReminderTime.defaultTime())
          } label: {
            Label(
              String(localized: "habits.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "plus.circle.fill")
          }
          .disabled(isMutating)
          .accessibilityIdentifier("mobileHabits.detail.reminders.add")
        }
      }
      .padding(LorvexDesign.Spacing.l)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("mobileHabits.detail.reminders")
      .sheet(item: $timeSheet) { context in
        MobileHabitReminderTimeSheet(
          initialTime: context.time,
          isNew: context.policy == nil
        ) { newTime in
          if let policy = context.policy {
            await setReminderTime?(policy, newTime)
          } else {
            await addReminder?(newTime)
          }
        }
        .lorvexSpatialBackground()
        .mobileCompactEditorSheetPresentation()
      }
    }
  }

  private func reminderRow(_ policy: HabitReminderPolicy) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: policy.enabled ? "bell.fill" : "bell.slash")
        .foregroundStyle(policy.enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        .frame(width: 22)
      Text(mobileClockTimeLabel(policy.reminderTime))
        .font(LorvexDesign.Typography.primaryText.weight(.medium))
        .strikethrough(!policy.enabled)
        .foregroundStyle(policy.enabled ? Color.primary : Color.secondary)
      Spacer(minLength: 8)
      if isInteractive {
        rowMenu(policy)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private func rowMenu(_ policy: HabitReminderPolicy) -> some View {
    Menu {
      Button {
        timeSheet = MobileHabitReminderTimeContext(policy: policy, time: policy.reminderTime)
      } label: {
        Label(
          String(localized: "habits.reminders.change_time", defaultValue: "Change Time", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "clock")
      }
      Button {
        Task { await toggleReminder?(policy) }
      } label: {
        Label(
          policy.enabled
            ? String(localized: "habits.reminders.disable", defaultValue: "Disable", table: "Localizable", bundle: MobileL10n.bundle)
            : String(localized: "habits.reminders.enable", defaultValue: "Enable", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: policy.enabled ? "bell.slash" : "bell")
      }
      Button(role: .destructive) {
        Task { await removeReminder?(policy) }
      } label: {
        Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .foregroundStyle(.secondary)
        .accessibilityLabel(String(localized: "habits.reminders.options", defaultValue: "Reminder options", table: "Localizable", bundle: MobileL10n.bundle))
    }
    .disabled(isMutating)
    .accessibilityIdentifier("mobileHabits.detail.reminders.menu")
  }
}

/// Identifies the reminder-time sheet's subject: a `policy` to retime, or `nil`
/// to add a fresh reminder seeded with `time`.
private struct MobileHabitReminderTimeContext: Identifiable {
  let id = UUID()
  let policy: HabitReminderPolicy?
  let time: String
}

/// A focused time-of-day picker sheet that commits an `HH:mm` string. Shared by
/// the add-reminder and change-time flows.
struct MobileHabitReminderTimeSheet: View {
  let isNew: Bool
  let commit: (String) async -> Void

  @State private var date: Date
  @State private var isSaving = false
  @Environment(\.dismiss) private var dismiss

  init(initialTime: String, isNew: Bool, commit: @escaping (String) async -> Void) {
    self.isNew = isNew
    self.commit = commit
    _date = State(initialValue: MobileHabitReminderTime.date(from: initialTime))
  }

  var body: some View {
    NavigationStack {
      Form {
        DatePicker(
          String(localized: "habits.reminders.time", defaultValue: "Time", table: "Localizable", bundle: MobileL10n.bundle),
          selection: $date,
          displayedComponents: .hourAndMinute
        )
        .accessibilityIdentifier("mobileHabits.reminderTime.picker")
      }
      .navigationTitle(
        isNew
          ? String(localized: "habits.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: MobileL10n.bundle)
          : String(localized: "habits.reminders.change_time", defaultValue: "Change Time", table: "Localizable", bundle: MobileL10n.bundle)
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle)) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            let time = MobileHabitReminderTime.string(from: date)
            isSaving = true
            Task {
              await commit(time)
              dismiss()
            }
          } label: {
            if isSaving {
              ProgressView()
            } else {
              Text(String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: MobileL10n.bundle))
            }
          }
          .disabled(isSaving)
          .accessibilityIdentifier("mobileHabits.reminderTime.confirm")
        }
      }
    }
  }
}

/// `HH:mm` (24-hour) ⇄ `Date` conversion for the reminder-time picker, matching
/// the wire format `HabitReminderPolicy.reminderTime` stores.
enum MobileHabitReminderTime {
  static func date(from hourMinute: String) -> Date {
    MobileStore.hmFormatter.date(from: hourMinute) ?? defaultDate()
  }

  static func string(from date: Date) -> String {
    MobileStore.hmFormatter.string(from: date)
  }

  static func defaultTime() -> String { string(from: defaultDate()) }

  private static func defaultDate() -> Date {
    Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
  }
}
