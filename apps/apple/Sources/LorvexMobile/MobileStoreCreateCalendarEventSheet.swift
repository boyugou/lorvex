import SwiftUI

struct MobileStoreCreateCalendarEventSheet: View {
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool
  @FocusState private var focusedField: Field?

  private enum Field {
    case title
    case location
    case notes
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(
          String(
            localized: "calendar.section.event", defaultValue: "Event", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          TextField(
            String(
              localized: "calendar.field.title", defaultValue: "Title", table: "Localizable",
              bundle: MobileL10n.bundle), text: $store.calendarDraft.title
          )
          .focused($focusedField, equals: .title)
          .submitLabel(.next)
          .onSubmit { focusedField = .location }
          .accessibilityIdentifier("mobileCreateCalendarEvent.title")
          DatePicker(
            String(
              localized: "calendar.field.date", defaultValue: "Date", table: "Localizable",
              bundle: MobileL10n.bundle), selection: $store.calendarDraft.date,
            displayedComponents: .date
          )
          .accessibilityIdentifier("mobileCreateCalendarEvent.date")
          Toggle(
            String(
              localized: "calendar.field.all_day", defaultValue: "All Day", table: "Localizable",
              bundle: MobileL10n.bundle), isOn: $store.calendarDraft.allDay
          )
          .accessibilityIdentifier("mobileCreateCalendarEvent.allDay")
          if !store.calendarDraft.allDay {
            DatePicker(
              String(
                localized: "calendar.field.start", defaultValue: "Start", table: "Localizable",
                bundle: MobileL10n.bundle),
              selection: $store.calendarDraft.startTime,
              displayedComponents: .hourAndMinute
            )
            .accessibilityIdentifier("mobileCreateCalendarEvent.startTime")
            DatePicker(
              String(
                localized: "calendar.field.end", defaultValue: "End", table: "Localizable",
                bundle: MobileL10n.bundle),
              selection: $store.calendarDraft.endTime,
              displayedComponents: .hourAndMinute
            )
            .accessibilityIdentifier("mobileCreateCalendarEvent.endTime")
            if !store.calendarDraft.timesValid {
              Label(
                String(
                  localized: "calendar.event.end_after_start.help",
                  defaultValue: "The end time must be after the start time", table: "Localizable",
                  bundle: MobileL10n.bundle),
                systemImage: "exclamationmark.triangle"
              )
              .font(.footnote)
              .foregroundStyle(.orange)
              .accessibilityIdentifier("mobileCreateCalendarEvent.timesInvalid")
            }
          }
          TextField(
            String(
              localized: "calendar.field.location", defaultValue: "Location", table: "Localizable",
              bundle: MobileL10n.bundle), text: $store.calendarDraft.location
          )
          .focused($focusedField, equals: .location)
          .submitLabel(.next)
          .onSubmit { focusedField = .notes }
          .accessibilityIdentifier("mobileCreateCalendarEvent.location")
        }

        Section(
          String(
            localized: "calendar.section.notes", defaultValue: "Notes", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          TextField(
            String(
              localized: "calendar.field.notes", defaultValue: "Notes", table: "Localizable",
              bundle: MobileL10n.bundle), text: $store.calendarDraft.notes, axis: .vertical
          )
          .lineLimit(3...6)
          .focused($focusedField, equals: .notes)
          .submitLabel(.done)
          .onSubmit { submit() }
          .accessibilityIdentifier("mobileCreateCalendarEvent.notes")
        }
      }
      .navigationTitle(
        String(
          localized: "sheet.new_event", defaultValue: "New Event", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            isPresented = false
          }
          .accessibilityIdentifier("mobileCreateCalendarEvent.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            submit()
          } label: {
            if store.isMutatingCalendarEvent {
              ProgressView()
            } else {
              Text(
                String(
                  localized: "common.create", defaultValue: "Create", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .disabled(!store.canCreateCalendarDraft)
          .accessibilityIdentifier("mobileCreateCalendarEvent.confirm")
        }
      }
    }
    // Calendar event editor detents: medium + large for schedule edits from every calendar entry point.
    .mobileCompactEditorSheetPresentation()
  }

  private func submit() {
    Task {
      let created = await store.createDraftCalendarEvent()
      if created {
        isPresented = false
      }
    }
  }
}
