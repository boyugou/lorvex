import LorvexCore
import SwiftUI

/// The calm field panels shared by the create and edit calendar-event sheets.
struct CalendarEventFormFields: View {
  @Bindable var store: AppStore
  let idPrefix: String
  /// Claimed when the sheet appears so the user can type immediately.
  @FocusState private var titleFocused: Bool
  /// The user's writable EventKit calendars, for the calendar picker. Empty
  /// (row hidden) until loaded, or when calendar integration is off — then the
  /// event lands in the dedicated Lorvex calendar with no choice to offer.
  @State private var writableCalendars: [EventKitCalendarDescriptor] = []

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      DraftSheetPanel(accessibilityIdentifier: "\(idPrefix).eventFields") {
        DraftSheetField(
          title: String(localized: "calendar.field.title", defaultValue: "Title", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "text.cursor"
        ) {
          TextField(
            String(localized: "calendar.field.title", defaultValue: "Title", table: "Localizable", bundle: LorvexL10n.bundle),
            text: $store.draftCalendarTitle
          )
          .font(LorvexDesign.Typography.primaryText)
          .textFieldStyle(.plain)
          .focused($titleFocused)
          .accessibilityLabel(String(
            localized: "calendar.event_title.a11y",
            defaultValue: "Event title",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
          .accessibilityIdentifier("\(idPrefix).title")
        }

        DraftSheetControlRow(
          title: String(localized: "calendar.field.date", defaultValue: "Date", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "calendar"
        ) {
          // Date chip + custom mini-month popover, matching the task
          // inspector; an event always has a date, so there is no clear.
          LorvexDateChip(
            date: store.draftCalendarDate,
            placeholder: String(
              localized: "calendar.field.date", defaultValue: "Date",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            onSet: { store.draftCalendarDate = $0 }
          )
          .accessibilityLabel(String(
            localized: "calendar.event_date.a11y",
            defaultValue: "Event date",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
          .accessibilityIdentifier("\(idPrefix).date")
        }

        DraftSheetControlRow(
          title: String(localized: "calendar.field.all_day", defaultValue: "All Day", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "sun.max"
        ) {
          Toggle("", isOn: $store.draftCalendarAllDay)
            .labelsHidden()
            .accessibilityLabel(String(
              localized: "calendar.field.all_day",
              defaultValue: "All Day",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ))
            .accessibilityIdentifier("\(idPrefix).allDay")
        }

        if !store.draftCalendarAllDay {
          DraftSheetControlRow(
            title: String(localized: "calendar.field.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "clock"
          ) {
            LorvexTimeChip(
              date: store.draftCalendarStartTime,
              accessibilityIdentifier: "\(idPrefix).startTime",
              onSet: { store.draftCalendarStartTime = $0 }
            )
            .accessibilityLabel(String(
              localized: "calendar.start_time.a11y",
              defaultValue: "Start time",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ))
          }

          DraftSheetControlRow(
            title: String(localized: "calendar.field.end", defaultValue: "End", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "timer"
          ) {
            LorvexTimeChip(
              date: store.draftCalendarEndTime,
              accessibilityIdentifier: "\(idPrefix).endTime",
              onSet: { store.draftCalendarEndTime = $0 }
            )
            .accessibilityLabel(String(
              localized: "calendar.end_time.a11y",
              defaultValue: "End time",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ))
          }
        }

        DraftSheetField(
          title: String(localized: "calendar.field.location", defaultValue: "Location", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "mappin.and.ellipse"
        ) {
          TextField(
            String(localized: "calendar.field.location", defaultValue: "Location", table: "Localizable", bundle: LorvexL10n.bundle),
            text: $store.draftCalendarLocation
          )
          .font(LorvexDesign.Typography.primaryText)
          .textFieldStyle(.plain)
          .accessibilityLabel(String(
            localized: "calendar.event_location.a11y",
            defaultValue: "Event location",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
          .accessibilityIdentifier("\(idPrefix).location")
        }

        if !writableCalendars.isEmpty {
          calendarPickerRow
        }

        LorvexColorField(color: $store.draftCalendarColor, idPrefix: idPrefix)

        CalendarEventRepeatField(
          recurrence: $store.draftCalendarRecurrence,
          isOpaque: store.draftCalendarRecurrenceIsOpaque,
          referenceDate: store.draftCalendarDate,
          idPrefix: idPrefix)
      }

      DraftSheetPanel(accessibilityIdentifier: "\(idPrefix).notesFields") {
        DraftSheetField(
          title: String(localized: "calendar.section.notes", defaultValue: "Notes", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "note.text"
        ) {
          LorvexPlainTextEditor(
            text: $store.draftCalendarNotes,
            placeholder: String(localized: "calendar.section.notes", defaultValue: "Notes", table: "Localizable", bundle: LorvexL10n.bundle),
            minHeight: 80,
            fontSize: 14
          )
          .accessibilityLabel(String(
            localized: "calendar.event_notes.a11y",
            defaultValue: "Event notes",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
          .accessibilityIdentifier("\(idPrefix).notes")
        }
      }
    }
    .task {
      titleFocused = false
      await Task.yield()
      titleFocused = true
    }
    .task {
      writableCalendars = (try? await store.loadWritableEventKitCalendars()) ?? []
    }
  }

  /// The writable-calendar chooser: a native menu picker whose default option is
  /// the dedicated Lorvex calendar (the `nil` selection), followed by each of the
  /// user's writable calendars with its color dot. Only shown when at least one
  /// writable calendar exists.
  private var calendarPickerRow: some View {
    DraftSheetControlRow(
      title: String(localized: "calendar.event.field.calendar", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "calendar"
    ) {
      Picker(selection: $store.draftCalendarTargetCalendarID) {
        calendarLabel(
          title: String(
            localized: "calendar.picker.lorvex_default", defaultValue: "Lorvex",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          dot: LorvexDesign.Palette.accent
        )
        .tag(String?.none)
        ForEach(writableCalendars) { calendar in
          calendarLabel(title: calendar.title, dot: Color(lorvexHex: calendar.colorHex) ?? .secondary)
            .tag(String?.some(calendar.id))
        }
      } label: {
        EmptyView()
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
      .accessibilityLabel(String(
        localized: "calendar.event_calendar.a11y",
        defaultValue: "Event calendar",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .accessibilityIdentifier("\(idPrefix).calendar")
    }
  }

  /// A calendar option: its color as a leading dot beside the title, the idiom
  /// Apple's own Calendar / Reminders pickers use.
  private func calendarLabel(title: String, dot: Color) -> some View {
    Label {
      Text(title)
    } icon: {
      Image(systemName: "circle.fill").foregroundStyle(dot)
    }
  }
}
