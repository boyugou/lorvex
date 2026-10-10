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
  /// The bell's column, grown with the body style the bell is set in.
  @ScaledMetric(relativeTo: .body) private var bellWidth: CGFloat = 22
  /// The vertical padding that takes Add Reminder's one line to a 44pt tap target.
  private static let addTapPadding: CGFloat = 12
  /// The time sheet's first detent, in points at the default text size: its
  /// one row needs far less than the half-height sheet's room.
  private static let timeSheetHeight: CGFloat = 200

  private var isInteractive: Bool { addReminder != nil }
  private var sortedPolicies: [HabitReminderPolicy] {
    policies.sorted { $0.reminderTime < $1.reminderTime }
  }

  var body: some View {
    if !policies.isEmpty || isInteractive {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        Label(String(localized: "habits.detail.reminders", defaultValue: "Reminders", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "bell")
          .font(LorvexDesign.Typography.sectionHeader)
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
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
              // The words are one line tall. The label's padding lifts the tap
              // target to 44pt, and the negative padding outside the button
              // gives the card that height back.
              Label(
                String(localized: "habits.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: MobileL10n.bundle),
                systemImage: "plus.circle.fill")
                .padding(.vertical, Self.addTapPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.vertical, -Self.addTapPadding)
            .disabled(isMutating)
            .accessibilityIdentifier("mobileHabits.detail.reminders.add")
          }
        }
        .padding(LorvexDesign.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
      }
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
        .mobileCompactEditorSheetPresentation(cardHeight: Self.timeSheetHeight)
      }
    }
  }

  /// The bell and the time are one accessibility element that reads the time
  /// and, for a reminder switched off, "Off" (the bell and the strikethrough
  /// say so only to the eye). The options menu is a button of its own beside
  /// it: combining the whole row would fold the menu into the time's element.
  private func reminderRow(_ policy: HabitReminderPolicy) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: policy.enabled ? "bell.fill" : "bell.slash")
          .foregroundStyle(policy.enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
          .frame(width: bellWidth)
          .accessibilityHidden(true)
        Text(lorvexClockTimeLabel(policy.reminderTime))
          .font(LorvexDesign.Typography.primaryText.weight(.medium))
          .strikethrough(!policy.enabled)
          .foregroundStyle(policy.enabled ? Color.primary : Color.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityValue(policy.enabled ? "" : Self.offLabel)
      Spacer(minLength: 8)
      if isInteractive {
        rowMenu(policy)
      }
    }
    .padding(.vertical, 2)
  }

  private static var offLabel: String {
    String(
      localized: "habits.reminders.off", defaultValue: "Off", table: "Localizable",
      bundle: MobileL10n.bundle)
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
      // A plain color, not the hierarchical `.secondary` style: a menu's label
      // takes the accent tint, and that style would draw a faint blue ring
      // instead of gray.
      Image(systemName: "ellipsis.circle")
        .foregroundStyle(Color.secondary)
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
      .mobileSheetTitle(
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
              ProgressView().tint(.white)
            } else {
              Text(String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
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
