import LorvexCore
import SwiftUI

/// The calendar create + edit form, presented as one modal sheet for both so a
/// new event and an existing one are authored through the identical surface and
/// size. `.create` opens the New Event form; `.edit(event)` opens the same form
/// seeded with the event's draft, adding a Delete affordance and — for a
/// recurring series — the This / This-and-Following / All occurrence-scope
/// choosers on Save and Delete.
struct CalendarEventSheet: View {
  enum Mode: Identifiable, Equatable {
    case create
    case edit(CalendarTimelineEvent)

    var id: String {
      switch self {
      case .create: "calendar.event.sheet.create"
      case .edit(let event): "calendar.event.sheet.edit.\(event.id)"
      }
    }
  }

  @Bindable var store: AppStore
  let mode: Mode
  /// Dismiss the sheet (clears the workspace's active-sheet state).
  let dismiss: () -> Void

  /// True while a create / save / delete round-trip (core write + EventKit
  /// write-back + timeline refresh) runs. The EventKit leg can take seconds — or
  /// block on a first-run permission prompt — so this gates the action buttons
  /// against a second submission and shows a spinner.
  @State private var isSubmitting = false
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingDeleteScopeDialog = false
  @State private var isShowingSaveScopeDialog = false

  private var editingEvent: CalendarTimelineEvent? {
    if case .edit(let event) = mode { return event }
    return nil
  }

  private var idPrefix: String { editingEvent == nil ? "createCalendarEvent" : "editCalendarEvent" }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(20)
      Divider()
      ScrollView {
        CalendarEventFormFields(store: store, idPrefix: idPrefix)
          .padding(20)
      }
      Divider()
      actionBar
        .padding(20)
    }
    .frame(minWidth: 500, idealWidth: 540, minHeight: 440, idealHeight: 580, maxHeight: 760)
    .accessibilityIdentifier("calendar.event.sheet")
    .confirmationDialog(
      String(
        localized: "calendar.edit_event.scope.title",
        defaultValue: "Save changes to this repeating event?",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      isPresented: $isShowingSaveScopeDialog,
      titleVisibility: .visible
    ) {
      if let event = editingEvent {
        if store.draftCalendarRecurrenceCanApplyToSingleOccurrence {
          Button(thisEventLabel) { runSave(scope: .thisEvent, event: event) }
        }
        Button(thisAndFollowingLabel) { runSave(scope: .thisAndFollowing, event: event) }
        Button(allEventsLabel) { runSave(scope: .allEvents, event: event) }
      }
      Button(cancelLabel, role: .cancel) {}
    } message: {
      Text(
        LocalizedStringResource(
          "calendar.edit_event.scope.message",
          defaultValue: "Choose which occurrences to update.",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
    }
    .confirmationDialog(
      editingEvent.map {
        String(
          format: String(
            localized: "calendar.delete_event.confirm.title",
            defaultValue: "Delete event \u{201C}%@\u{201D}?",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          $0.title)
      } ?? "",
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "common.delete", defaultValue: "Delete", table: "Localizable",
          bundle: LorvexL10n.bundle),
        role: .destructive
      ) {
        if let event = editingEvent { runDelete(scope: nil, event: event) }
      }
      Button(
        String(
          localized: "common.keep", defaultValue: "Keep", table: "Localizable",
          bundle: LorvexL10n.bundle), role: .cancel
      ) {}
    }
    .confirmationDialog(
      String(
        localized: "calendar.delete_event.scope.title",
        defaultValue: "Delete this repeating event?",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      isPresented: $isShowingDeleteScopeDialog,
      titleVisibility: .visible
    ) {
      if let event = editingEvent {
        Button(thisEventLabel) { runDelete(scope: .thisEvent, event: event) }
        Button(thisAndFollowingLabel) { runDelete(scope: .thisAndFollowing, event: event) }
        Button(
          String(
            localized: "calendar.recurring_scope.delete_all_events",
            defaultValue: "Delete All Events",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          role: .destructive
        ) { runDelete(scope: .allEvents, event: event) }
      }
      Button(cancelLabel, role: .cancel) {}
    } message: {
      Text(
        LocalizedStringResource(
          "calendar.delete_event.scope.message",
          defaultValue: "Choose which occurrences to delete.",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
    }
  }

  private var header: some View {
    DraftSheetHeader(
      title: editingEvent == nil
        ? String(
          localized: "calendar.create_event.title", defaultValue: "New Event", table: "Localizable",
          bundle: LorvexL10n.bundle)
        : String(
          localized: "calendar.edit_event.title", defaultValue: "Edit Event", table: "Localizable",
          bundle: LorvexL10n.bundle),
      subtitle: editingEvent?.title
        ?? String(
          localized: "calendar.create_event.description",
          defaultValue: "Place a real appointment on the calendar timeline.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
      systemImage: editingEvent == nil ? "calendar.badge.plus" : "calendar.badge.clock")
  }

  private var actionBar: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button(cancelLabel) { dismiss() }
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(cancelLabel)
        .accessibilityIdentifier("\(idPrefix).cancel")

      if let event = editingEvent, event.editable {
        // The sheet is the event's management surface, so deletion lives here;
        // recurring events choose an occurrence scope first.
        Button(role: .destructive) {
          if event.supportsScopedMutation {
            isShowingDeleteScopeDialog = true
          } else {
            isShowingDeleteConfirmation = true
          }
        } label: {
          Text(
            LocalizedStringResource(
              "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: LorvexL10n.bundle))
        }
        .buttonStyle(.lorvexSecondary)
        .disabled(isSubmitting)
        .accessibilityLabel(
          String(
            localized: "calendar.delete_event.a11y", defaultValue: "Delete event",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
        )
        .accessibilityIdentifier("editCalendarEvent.delete")
      }

      Spacer(minLength: LorvexDesign.Spacing.s)

      if isSubmitting {
        ProgressView().controlSize(.small)
      }

      Button(confirmTitle) { submit() }
        .buttonStyle(.lorvexPrimary)
        .keyboardShortcut(.defaultAction)
        .disabled(isConfirmDisabled)
        .help(confirmHelp)
        .accessibilityLabel(confirmAccessibilityLabel)
        .accessibilityIdentifier("\(idPrefix).confirm")
    }
    .controlSize(.small)
  }

  // MARK: Actions

  private func submit() {
    if let event = editingEvent {
      if event.supportsScopedMutation {
        isShowingSaveScopeDialog = true
      } else {
        runSave(scope: nil, event: event)
      }
    } else {
      isSubmitting = true
      Task {
        await store.createDraftCalendarEvent()
        isSubmitting = false
        if store.errorMessage == nil { dismiss() }
      }
    }
  }

  private func runSave(scope: CalendarEventEditScope?, event: CalendarTimelineEvent) {
    isSubmitting = true
    Task {
      if let scope {
        await store.saveScopedCalendarEvent(event, scope: scope)
      } else {
        await store.updateCalendarEvent(event)
      }
      isSubmitting = false
      if store.errorMessage == nil { dismiss() }
    }
  }

  private func runDelete(scope: CalendarEventEditScope?, event: CalendarTimelineEvent) {
    isSubmitting = true
    Task {
      if let scope {
        await store.deleteScopedCalendarEvent(event, scope: scope)
      } else {
        await store.deleteCalendarEvent(event)
      }
      isSubmitting = false
      if store.errorMessage == nil {
        store.clearSelectedCalendarEvent()
        dismiss()
      }
    }
  }

  // MARK: Enablement + labels

  private var isConfirmDisabled: Bool {
    isSubmitting
      || store.draftCalendarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !store.draftCalendarTimesValid
  }

  private var confirmTitle: String {
    editingEvent == nil
      ? String(
        localized: "common.create", defaultValue: "Create", table: "Localizable",
        bundle: LorvexL10n.bundle)
      : String(
        localized: "common.save", defaultValue: "Save", table: "Localizable",
        bundle: LorvexL10n.bundle)
  }

  private var confirmAccessibilityLabel: String {
    editingEvent == nil
      ? String(
        localized: "calendar.create_event.a11y", defaultValue: "Create event", table: "Localizable",
        bundle: LorvexL10n.bundle)
      : String(
        localized: "calendar.save_event.a11y", defaultValue: "Save event", table: "Localizable",
        bundle: LorvexL10n.bundle)
  }

  private var confirmHelp: String {
    if store.draftCalendarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return editingEvent == nil
        ? String(
          localized: "calendar.create_event.needs_title.help",
          defaultValue: "Add a title to create this event",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
        : String(
          localized: "calendar.save_event.needs_title.help",
          defaultValue: "Add a title to save this event",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
    }
    if !store.draftCalendarTimesValid {
      return String(
        localized: "calendar.event.end_after_start.help",
        defaultValue: "The end time must be after the start time",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return confirmAccessibilityLabel
  }

  private var cancelLabel: String {
    String(
      localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var thisEventLabel: String {
    String(
      localized: "calendar.recurring_scope.this_event", defaultValue: "This Event",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
  private var thisAndFollowingLabel: String {
    String(
      localized: "calendar.recurring_scope.this_and_following",
      defaultValue: "This and Following Events",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
  private var allEventsLabel: String {
    String(
      localized: "calendar.recurring_scope.all_events", defaultValue: "All Events",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
