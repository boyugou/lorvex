import LorvexCore
import SwiftUI

struct MobileStoreEditCalendarEventSheet: View {
  let event: CalendarTimelineEvent
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool

  @State private var isConfirmingDelete = false
  @State private var isShowingSaveScope = false
  @State private var isShowingDeleteScope = false
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
          .accessibilityIdentifier("mobileEditCalendarEvent.title")
          DatePicker(
            String(
              localized: "calendar.field.date", defaultValue: "Date", table: "Localizable",
              bundle: MobileL10n.bundle), selection: $store.calendarDraft.date,
            displayedComponents: .date
          )
          .accessibilityIdentifier("mobileEditCalendarEvent.date")
          Toggle(
            String(
              localized: "calendar.field.all_day", defaultValue: "All Day", table: "Localizable",
              bundle: MobileL10n.bundle), isOn: $store.calendarDraft.allDay
          )
          .accessibilityIdentifier("mobileEditCalendarEvent.allDay")
          if !store.calendarDraft.allDay {
            DatePicker(
              String(
                localized: "calendar.field.start", defaultValue: "Start", table: "Localizable",
                bundle: MobileL10n.bundle), selection: $store.calendarDraft.startTime,
              displayedComponents: .hourAndMinute
            )
            .accessibilityIdentifier("mobileEditCalendarEvent.startTime")
            DatePicker(
              String(
                localized: "calendar.field.end", defaultValue: "End", table: "Localizable",
                bundle: MobileL10n.bundle), selection: $store.calendarDraft.endTime,
              displayedComponents: .hourAndMinute
            )
            .accessibilityIdentifier("mobileEditCalendarEvent.endTime")
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
              .accessibilityIdentifier("mobileEditCalendarEvent.timesInvalid")
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
          .accessibilityIdentifier("mobileEditCalendarEvent.location")
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
          .onSubmit { attemptSave() }
          .accessibilityIdentifier("mobileEditCalendarEvent.notes")
        }

        // The default grid presentation has no swipe-to-delete (that lives only
        // in the list view), so the only delete affordance for a grid-selected
        // event is here. Confirm-gated because deletion is irreversible.
        if event.editable {
          Section {
            Button(role: .destructive) {
              requestDelete()
            } label: {
              Label(
                String(
                  localized: "common.delete", defaultValue: "Delete", table: "Localizable",
                  bundle: MobileL10n.bundle), systemImage: "trash")
            }
            .disabled(store.isMutatingCalendarEvent)
            .accessibilityIdentifier("mobileEditCalendarEvent.delete")
          }
        }
      }
      .navigationTitle(
        String(
          localized: "sheet.edit_event", defaultValue: "Edit Event", table: "Localizable",
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
          .accessibilityIdentifier("mobileEditCalendarEvent.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            attemptSave()
          } label: {
            if store.isMutatingCalendarEvent {
              ProgressView()
            } else {
              Text(
                String(
                  localized: "common.save", defaultValue: "Save", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .disabled(!store.canUpdateCalendarDraft)
          .accessibilityIdentifier("mobileEditCalendarEvent.confirm")
        }
      }
      .confirmationDialog(
        String(
          format: String(
            localized: "calendar.delete_event.confirm.title",
            defaultValue: "Delete event \u{201C}%@\u{201D}?", table: "Localizable",
            bundle: MobileL10n.bundle),
          event.title),
        isPresented: $isConfirmingDelete,
        titleVisibility: .visible
      ) {
        Button(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: MobileL10n.bundle), role: .destructive
        ) {
          Task {
            let deleted = await store.deleteCalendarEvent(event)
            if deleted { isPresented = false }
          }
        }
        Button(
          String(
            localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
            bundle: MobileL10n.bundle), role: .cancel
        ) {}
      }
      .confirmationDialog(
        String(
          localized: "calendar.edit_event.scope.title",
          defaultValue: "Save changes to this repeating event?", table: "Localizable",
          bundle: MobileL10n.bundle),
        isPresented: $isShowingSaveScope,
        titleVisibility: .visible
      ) {
        scopeButtons(isDelete: false)
      } message: {
        Text(
          String(
            localized: "calendar.edit_event.scope.message",
            defaultValue: "Choose which occurrences to update.", table: "Localizable",
            bundle: MobileL10n.bundle))
      }
      .confirmationDialog(
        String(
          localized: "calendar.delete_event.scope.title",
          defaultValue: "Delete this repeating event?", table: "Localizable",
          bundle: MobileL10n.bundle),
        isPresented: $isShowingDeleteScope,
        titleVisibility: .visible
      ) {
        scopeButtons(isDelete: true)
      } message: {
        Text(
          String(
            localized: "calendar.delete_event.scope.message",
            defaultValue: "Choose which occurrences to delete.", table: "Localizable",
            bundle: MobileL10n.bundle))
      }
    }
    // Calendar event editor detents: medium + large for schedule edits from every calendar entry point.
    .mobileCompactEditorSheetPresentation()
  }

  // A recurring event routes save/delete through the occurrence-vs-following-vs-
  // series choice (matching macOS + the scoped-edit MCP contract); a one-off
  // event edits/deletes directly.
  @ViewBuilder
  private func scopeButtons(isDelete: Bool) -> some View {
    Button(
      String(
        localized: "calendar.recurring_scope.this_event", defaultValue: "This Event",
        table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      run(scope: .thisEvent, isDelete: isDelete)
    }
    .accessibilityIdentifier("mobileEditCalendarEvent.scope.thisEvent")
    Button(
      String(
        localized: "calendar.recurring_scope.this_and_following",
        defaultValue: "This and Following Events", table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      run(scope: .thisAndFollowing, isDelete: isDelete)
    }
    .accessibilityIdentifier("mobileEditCalendarEvent.scope.thisAndFollowing")
    Button(
      isDelete
        ? String(
          localized: "calendar.recurring_scope.delete_all_events",
          defaultValue: "Delete All Events", table: "Localizable", bundle: MobileL10n.bundle)
        : String(
          localized: "calendar.recurring_scope.all_events", defaultValue: "All Events",
          table: "Localizable", bundle: MobileL10n.bundle),
      role: isDelete ? .destructive : nil
    ) {
      run(scope: .allEvents, isDelete: isDelete)
    }
    .accessibilityIdentifier("mobileEditCalendarEvent.scope.allEvents")
    Button(
      String(
        localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
        bundle: MobileL10n.bundle), role: .cancel
    ) {}
  }

  private func attemptSave() {
    if event.supportsScopedMutation {
      isShowingSaveScope = true
    } else {
      Task {
        let updated = await store.updateCalendarEvent(event)
        if updated { isPresented = false }
      }
    }
  }

  private func requestDelete() {
    if event.supportsScopedMutation {
      isShowingDeleteScope = true
    } else {
      isConfirmingDelete = true
    }
  }

  private func run(scope: CalendarEventEditScope, isDelete: Bool) {
    Task {
      let succeeded =
        isDelete
        ? await store.deleteScopedCalendarEvent(event, scope: scope)
        : await store.saveScopedCalendarEvent(event, scope: scope)
      if succeeded { isPresented = false }
    }
  }
}
