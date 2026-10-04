import LorvexCore
import SwiftUI

/// The agenda list: each listed day's events and tasks under a header naming
/// the day, in the day's reading order (``MobileCalendarAgendaDay/entries``;
/// see ``MobileCalendarAgendaDay/listed(_:todayKey:pinnedDayKey:)`` for which
/// days are listed). An event the clock has passed steps back (its glyph
/// fades and its title turns secondary), the way Today treats the schedule
/// rows it has cleared; a task keeps full strength until it is done, since an
/// unfinished one still needs doing. A task row completes, swipes, and
/// long-presses as every task row does, and drags onto a calendar day to
/// plan it there. A free today, or a free pinned day, reads "Nothing
/// planned"; so does an agenda with no day to list.
struct MobileCalendarAgendaPanel: View {
  /// Where the agenda stands: `.beside` the grid, a sidebar list on its own
  /// grouped background, as beside an iPad's grid; or `.under` it, a plain
  /// list that continues the grid's surface, as under the month grid of an
  /// upright phone.
  enum Placement {
    case beside
    case under
  }

  /// Every visible day, in order; the panel picks the ones it lists.
  let days: [MobileCalendarAgendaDay]
  /// The logical today as `yyyy-MM-dd`.
  let todayKey: String
  /// A day as `yyyy-MM-dd` listed even when it is free, like today: the day
  /// a month grid has chosen. Nil lists only today and the days with entries.
  var pinnedDayKey: String? = nil
  var placement: Placement = .beside
  /// The current time in minutes since midnight, or `nil` when unknown.
  let nowMinutes: Int?
  let calendar: Calendar
  /// Whether an event edit or delete is in flight.
  let isMutating: Bool
  let editEvent: (CalendarTimelineEvent) -> Void
  let deleteEvent: (CalendarTimelineEvent) async -> Bool
  let deleteScopedEvent: (CalendarTimelineEvent, CalendarEventEditScope) async -> Bool
  let openTask: (LorvexTask) -> Void
  /// The completion, start/pause, and defer actions of a task's row.
  let taskActions: (LorvexTask) -> MobileTaskRowActions
  /// Whether a change to the task is in flight.
  let taskIsMutating: (LorvexTask.ID) -> Bool
  /// Whether the task waits on an unfinished task, so its row reads Blocked
  /// and offers no Start.
  let taskIsBlocked: (LorvexTask.ID) -> Bool
  @State private var eventAwaitingDeleteScope: CalendarTimelineEvent?

  var body: some View {
    styledList
      .navigationTitle(
        String(
          localized: "calendar.agenda", defaultValue: "Agenda", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileCalendar.agendaPanel")
      .mobileCalendarDeleteScopeDialog(
        event: $eventAwaitingDeleteScope,
        delete: deleteScopedEvent)
  }

  @ViewBuilder
  private var styledList: some View {
    switch placement {
    case .beside: list.listStyle(.sidebar)
    case .under:
      list.listStyle(.plain)
        // The plain list's opening gap would float the day's header well
        // below the grid it continues.
        .contentMargins(.top, LorvexDesign.Spacing.xs, for: .scrollContent)
    }
  }

  private var list: some View {
    List {
      ForEach(listedDays) { day in
        Section {
          if day.isEmpty {
            nothingPlannedRow
          }
          ForEach(day.entries) { entry in
            switch entry {
            case .event(let event):
              eventRow(
                event, dayKey: day.key,
                isPast: day.hasPassed(event, todayKey: todayKey, nowMinutes: nowMinutes))
            case .task(let task):
              MobileCalendarAgendaTaskRow(
                task: task, dayKey: day.key, isMutating: taskIsMutating(task.id),
                isBlocked: taskIsBlocked(task.id), actions: taskActions(task),
                open: { openTask(task) })
            }
          }
        } header: {
          header(for: day)
        }
      }

      if listedDays.isEmpty {
        Section { nothingPlannedRow }
      }
    }
  }

  private func eventRow(_ event: CalendarTimelineEvent, dayKey: String, isPast: Bool) -> some View {
    Button {
      editEvent(event)
    } label: {
      MobileCalendarAgendaRow(event: event, dayKey: dayKey, isPast: isPast)
    }
    .buttonStyle(.plain)
    .lorvexRowHoverEffect()
    .disabled(!event.editable)
    .contextMenu {
      if event.editable {
        Button {
          editEvent(event)
        } label: {
          Label(
            String(
              localized: "common.edit", defaultValue: "Edit", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "pencil")
        }
        .disabled(isMutating)

        Button(role: .destructive) {
          requestDelete(event)
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
        .disabled(isMutating)
      }
    }
  }

  private func requestDelete(_ event: CalendarTimelineEvent) {
    if event.supportsScopedMutation {
      eventAwaitingDeleteScope = event
    } else {
      Task { _ = await deleteEvent(event) }
    }
  }

  private var listedDays: [MobileCalendarAgendaDay] {
    MobileCalendarAgendaDay.listed(days, todayKey: todayKey, pinnedDayKey: pinnedDayKey)
  }

  private var nothingPlannedRow: some View {
    Text(
      String(
        localized: "calendar.agenda.empty", defaultValue: "Nothing planned", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .font(LorvexDesign.Typography.secondaryText)
    .foregroundStyle(.secondary)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .accessibilityIdentifier("mobileCalendar.agenda.empty")
  }

  /// A day's name over its date. Both take the section header's own color:
  /// a List header already draws in the secondary style, and a hierarchical
  /// `.secondary` inside it would compound to about 2.3:1.
  private func header(for day: MobileCalendarAgendaDay) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(dayTitle(day))
        .font(LorvexDesign.Typography.primaryEmphasis)
      Text(dateLine(day.date))
        .font(LorvexDesign.Typography.tertiaryText)
    }
    .textCase(nil)
  }

  /// The day's date, without the year inside the current year: the week
  /// header above already names it.
  private func dateLine(_ date: Date) -> String {
    calendar.isDate(date, equalTo: Date(), toGranularity: .year)
      ? LorvexDateFormatters.string(date, template: "MMMd", timeZone: calendar.timeZone)
      : LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: calendar.timeZone)
  }

  /// "Today" on the logical today, the day the week strips mark, else the
  /// weekday.
  private func dayTitle(_ day: MobileCalendarAgendaDay) -> String {
    if day.key == todayKey {
      return String(
        localized: "calendar.today", defaultValue: "Today", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    return LorvexDateFormatters.string(
      day.date, template: "EEEE", timeZone: calendar.timeZone, position: .leading)
  }
}
