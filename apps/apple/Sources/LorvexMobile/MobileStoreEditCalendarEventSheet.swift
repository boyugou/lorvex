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
              bundle: MobileL10n.bundle), text: $store.calendarDraft.title, axis: .vertical
          )
          .lineLimit(1...)
          .focused($focusedField, equals: .title)
          .submitLabel(.next)
          .onSubmit { focusedField = .location }
          .accessibilityIdentifier("mobileEditCalendarEvent.title")
          MobileCalendarEventTimingRows(
            timing: $store.calendarDraft.timing, idPrefix: "mobileEditCalendarEvent")
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
          Section { deleteButton }
        }
      }
      .mobileSheetTitle(
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

        ToolbarItem(placement: .confirmationAction) { saveButton }
      }
    }
    // The event form is a dense form, so it opens at full height.
    .mobileFullEditorSheetPresentation()
  }

  // Each confirmation dialog is attached to the button that raises it: on the
  // iPhone a confirmation dialog is a popover that points at the view carrying
  // the modifier, so attaching it to the form would put it away from the control.

  private var deleteButton: some View {
    Button(role: .destructive) {
      requestDelete()
    } label: {
      Label(
        String(
          localized: "common.delete", defaultValue: "Delete", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "trash")
    }
    .mobileDestructiveRowStyle()
    .disabled(store.isMutatingCalendarEvent)
    .accessibilityIdentifier("mobileEditCalendarEvent.delete")
    .mobileDeleteConfirmation(
      isPresented: $isConfirmingDelete,
      title: String(
        format: String(
          localized: "calendar.delete_event.confirm.title",
          defaultValue: "Delete event \u{201C}%@\u{201D}?", table: "Localizable",
          bundle: MobileL10n.bundle),
        event.title)
    ) {
      Task {
        let deleted = await store.deleteCalendarEvent(event)
        if deleted { isPresented = false }
      }
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

  private var saveButton: some View {
    Button {
      attemptSave()
    } label: {
      if store.isMutatingCalendarEvent {
        ProgressView().tint(.white)
      } else {
        Text(
          String(
            localized: "common.save", defaultValue: "Save", table: "Localizable",
            bundle: MobileL10n.bundle))
      }
    }
    .mobileProminentToolbarButtonStyle()
    .disabled(!store.canUpdateCalendarDraft)
    .accessibilityIdentifier("mobileEditCalendarEvent.confirm")
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
      Text(saveScopeMessage)
    }
  }

  // A recurring event routes save/delete through the occurrence-vs-following-vs-
  // series choice (matching macOS + the scoped-edit MCP contract); a one-off
  // event edits/deletes directly.
  @ViewBuilder
  private func scopeButtons(isDelete: Bool) -> some View {
    // The save and delete scope dialogs share this builder but must expose
    // distinct identifiers: the "this event" / "this and following" buttons are
    // otherwise identical, so a single `.scope.thisEvent` id can't tell a test
    // (or accessibility inspection) which intent's dialog it belongs to.
    let intent = isDelete ? "delete" : "save"
    Button(
      String(
        localized: "calendar.recurring_scope.this_event", defaultValue: "This Event",
        table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      run(scope: .thisEvent, isDelete: isDelete)
    }
    .accessibilityIdentifier("mobileEditCalendarEvent.\(intent).scope.thisEvent")
    Button(
      String(
        localized: "calendar.recurring_scope.this_and_following",
        defaultValue: "This and Following Events", table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      run(scope: .thisAndFollowing, isDelete: isDelete)
    }
    .accessibilityIdentifier("mobileEditCalendarEvent.\(intent).scope.thisAndFollowing")
    // A new length in days applies from this occurrence on: an all-events
    // edit would write it onto the series' own first day.
    if isDelete || store.calendarDraft.timing.keepsDaySpan(of: event) {
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
      .accessibilityIdentifier("mobileEditCalendarEvent.\(intent).scope.allEvents")
    }
    Button(
      String(
        localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
        bundle: MobileL10n.bundle), role: .cancel
    ) {}
  }

  /// The save dialog's message: the prompt, and under it a note on what All
  /// Events does to single-occurrence changes and cancelled days. The note shows
  /// only when All Events would reset a single-occurrence change that is loaded
  /// in the calendar timeline (``CalendarAllEventsNote``). This form does not
  /// edit the repeat rule.
  private var saveScopeMessage: String {
    let prompt = String(
      localized: "calendar.edit_event.scope.message",
      defaultValue: "Choose which occurrences to update.", table: "Localizable",
      bundle: MobileL10n.bundle)
    guard
      CalendarAllEventsNote.isShown(
        editing: event, draft: store.calendarDraft.timing,
        loadedEvents: store.calendarTimeline?.events ?? [])
    else { return prompt }
    let note = String(
      localized: "calendar.edit_event.scope.all_events_note",
      defaultValue:
        "All Events also resets changes you made to single occurrences. Cancelled occurrences stay cancelled.",
      table: "Localizable", bundle: MobileL10n.bundle)
    return "\(prompt)\n\n\(note)"
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
