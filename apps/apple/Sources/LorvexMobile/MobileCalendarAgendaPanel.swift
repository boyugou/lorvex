import LorvexCore
import SwiftUI

struct MobileCalendarAgendaDay: Identifiable, Equatable {
  let date: Date
  let events: [CalendarTimelineEvent]
  let tasks: [LorvexTask]

  var id: Date { date }
  var isEmpty: Bool { events.isEmpty && tasks.isEmpty }
}

struct MobileCalendarAgendaPanel: View {
  let days: [MobileCalendarAgendaDay]
  let calendar: Calendar
  let isMutating: Bool
  let createEvent: () -> Void
  let editEvent: (CalendarTimelineEvent) -> Void
  let deleteEvent: (CalendarTimelineEvent) async -> Bool
  let deleteScopedEvent: (CalendarTimelineEvent, CalendarEventEditScope) async -> Bool
  let openTask: (LorvexTask) -> Void
  @State private var eventAwaitingDeleteScope: CalendarTimelineEvent?

  var body: some View {
    List {
      Section {
        Button {
          createEvent()
        } label: {
          Label(
            String(
              localized: "calendar.new_event", defaultValue: "New Event", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "plus")
        }
        .lorvexRowHoverEffect()
        .accessibilityIdentifier("mobileCalendar.agendaCreate")
      }

      ForEach(days) { day in
        Section {
          if day.isEmpty {
            Text(
              String(
                localized: "calendar.empty.no_events", defaultValue: "No Events",
                table: "Localizable", bundle: MobileL10n.bundle)
            )
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
          } else {
            ForEach(day.events) { event in
              Button {
                editEvent(event)
              } label: {
                MobileCalendarAgendaRow(event: event)
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
            ForEach(day.tasks) { task in
              Button {
                openTask(task)
              } label: {
                MobileCalendarAgendaTaskRow(task: task)
              }
              .buttonStyle(.plain)
              .lorvexRowHoverEffect()
            }
          }
        } header: {
          header(for: day.date)
        }
      }
    }
    .listStyle(.sidebar)
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

  private func requestDelete(_ event: CalendarTimelineEvent) {
    if event.supportsScopedMutation {
      eventAwaitingDeleteScope = event
    } else {
      Task { _ = await deleteEvent(event) }
    }
  }

  private func header(for date: Date) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(dayTitle(date))
        .font(LorvexDesign.Typography.primaryEmphasis)
      Text(Self.fullDateFormatter.string(from: date))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
    }
    .textCase(nil)
  }

  private func dayTitle(_ date: Date) -> String {
    if calendar.isDateInToday(date) {
      return String(
        localized: "calendar.today", defaultValue: "Today", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    return Self.weekdayFormatter.string(from: date)
  }

  private static let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.dateFormat = "EEEE"
    return formatter
  }()

  private static let fullDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()
}
