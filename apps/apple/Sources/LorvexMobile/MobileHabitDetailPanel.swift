import LorvexCore
import SwiftUI

struct MobileHabitDetailPanel: View {
  let habit: LorvexHabit
  let detail: MobileStore.HabitDetail?
  let isMutating: Bool
  let editHabit: () -> Void
  let deleteHabit: () async -> Bool
  let complete: () async -> Bool
  let reset: () async -> Bool
  // Reminder-editing closures. When supplied the reminders block is interactive
  // (add / retime / enable-disable / remove); when nil it renders read-only.
  var addReminder: ((String) async -> Void)? = nil
  var setReminderTime: ((HabitReminderPolicy, String) async -> Void)? = nil
  var toggleReminder: ((HabitReminderPolicy) async -> Void)? = nil
  var removeReminder: ((HabitReminderPolicy) async -> Void)? = nil

  @State private var isConfirmingDelete = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
        header
        metricsGrid
        if let milestone = habit.milestone {
          MobileHabitMilestoneProgressView(
            milestone: milestone,
            frequencyType: habit.frequencyType,
            tint: habit.tileTint,
            style: .detail
          )
          .padding(LorvexDesign.Spacing.l)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        MobileHabitVisualizationSection(habit: habit, detail: detail)
        MobileHabitReminderList(
          policies: detail?.reminderPolicies ?? [],
          isMutating: isMutating,
          addReminder: addReminder,
          setReminderTime: setReminderTime,
          toggleReminder: toggleReminder,
          removeReminder: removeReminder)
        actions
      }
      .frame(maxWidth: 720, alignment: .leading)
      .padding(LorvexDesign.Spacing.xl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.background)
    .accessibilityIdentifier("mobileHabits.detail.panel")
    .confirmationDialog(
      String(
        format: String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: MobileL10n.bundle),
        habit.name),
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), role: .destructive) {
        Task { _ = await deleteHabit() }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle), role: .cancel) {}
    } message: {
      Text(String(localized: "habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(icon: habit.icon, fallback: "repeat", tint: habit.tileTint, size: 56)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        Text(habit.name)
          .font(LorvexDesign.Typography.sectionHeader)
        if let encouragement = habit.cue, !encouragement.isEmpty {
          // The encouragement — a motivating line, set as an inspiring callout
          // (a sparkle + italic), not a dry context label.
          HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
            Image(systemName: "sparkles")
              .font(.footnote)
              .foregroundStyle(habit.tileTint)
            Text(encouragement)
              .font(LorvexDesign.Typography.primaryText)
              .italic()
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private var metricsGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: LorvexDesign.Spacing.l, verticalSpacing: LorvexDesign.Spacing.l) {
      GridRow {
        metric(
          title: String(localized: "habits.detail.today", defaultValue: "Today", table: "Localizable", bundle: MobileL10n.bundle),
          value: habit.todayProgressText,
          systemImage: habit.isCompleteToday ? "checkmark.circle.fill" : "circle.dashed")
        metric(
          title: String(localized: "habits.detail.total", defaultValue: "Total", table: "Localizable", bundle: MobileL10n.bundle),
          value: "\(habit.totalCompletions)",
          systemImage: "sum")
      }
      GridRow {
        metric(
          title: String(localized: "habits.detail.rate_30d", defaultValue: "30-day", table: "Localizable", bundle: MobileL10n.bundle),
          value: percentText,
          systemImage: "chart.line.uptrend.xyaxis")
        metric(
          title: String(localized: "habits.detail.frequency", defaultValue: "Frequency", table: "Localizable", bundle: MobileL10n.bundle),
          value: MobileHabitDisplayText.frequencyName(habit.frequencyType),
          systemImage: "calendar.badge.clock")
      }
    }
  }

  private func metric(title: String, value: String, systemImage: String) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Label(title, systemImage: systemImage)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
      Text(value)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(LorvexDesign.Spacing.l)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var actions: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Button {
        Task {
          if habit.isCompleteToday {
            _ = await reset()
          } else {
            _ = await complete()
          }
        }
      } label: {
        Label(
          habit.isCompleteToday
          ? String(localized: "habits.detail.reset", defaultValue: "Reset Today", table: "Localizable", bundle: MobileL10n.bundle)
          : String(localized: "habits.detail.complete", defaultValue: "Complete Today", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: habit.isCompleteToday ? "arrow.counterclockwise" : "checkmark")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isMutating)

      Button {
        editHabit()
      } label: {
        Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .buttonStyle(.bordered)
      .disabled(isMutating)

      Button(role: .destructive) {
        isConfirmingDelete = true
      } label: {
        Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
      }
      .buttonStyle(.bordered)
      .disabled(isMutating)
    }
  }

  private var percentText: String {
    habit.completionRate30d.formatted(.percent.precision(.fractionLength(0)))
  }
}
