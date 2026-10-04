import LorvexCore
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
              bundle: MobileL10n.bundle), text: $store.calendarDraft.title, axis: .vertical
          )
          .lineLimit(1...)
          .focused($focusedField, equals: .title)
          .submitLabel(.next)
          .onSubmit { focusedField = .location }
          .accessibilityIdentifier("mobileCreateCalendarEvent.title")
          MobileCalendarEventTimingRows(
            timing: $store.calendarDraft.timing, idPrefix: "mobileCreateCalendarEvent")
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
      .mobileSheetTitle(
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
              ProgressView().tint(.white)
            } else {
              Text(
                String(
                  localized: "common.create", defaultValue: "Create", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!store.canCreateCalendarDraft)
          .accessibilityIdentifier("mobileCreateCalendarEvent.confirm")
        }
      }
    }
    // The event form is a dense form, so it opens at full height.
    .mobileFullEditorSheetPresentation()
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
