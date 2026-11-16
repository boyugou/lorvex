import SwiftUI

public struct CalendarDuplicateGroupingPicker: View {
  @Binding var selection: CalendarDuplicateGrouping

  public init(selection: Binding<CalendarDuplicateGrouping>) { self._selection = selection }

  public var body: some View {
    Picker(selection: $selection) {
      ForEach(CalendarDuplicateGrouping.allCases, id: \.self) { mode in
        Text(mode.title).tag(mode)
      }
    } label: {
      Text(
        String(
          localized: "calendar.duplicates.setting", defaultValue: "Combine Duplicate Events",
          table: "Localizable", bundle: CoreL10n.bundle))
    }
    .accessibilityIdentifier("settings.calendar.duplicateGrouping")
  }
}

extension CalendarDuplicateGrouping {
  public var title: String {
    switch self {
    case .off:
      String(
        localized: "calendar.duplicates.off", defaultValue: "Off", table: "Localizable",
        bundle: CoreL10n.bundle)
    case .strict:
      String(
        localized: "calendar.duplicates.strict", defaultValue: "Matching Details",
        table: "Localizable", bundle: CoreL10n.bundle)
    case .titleAndTime:
      String(
        localized: "calendar.duplicates.titleTime", defaultValue: "Same Title and Time",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
  }

  public var detail: String {
    switch self {
    case .off:
      String(
        localized: "calendar.duplicates.off.detail",
        defaultValue: "Show every source copy separately.", table: "Localizable",
        bundle: CoreL10n.bundle)
    case .strict:
      String(
        localized: "calendar.duplicates.strict.detail",
        defaultValue:
          "Combine events across calendars only when their title, time and details match. Every copy remains available in event details.",
        table: "Localizable", bundle: CoreL10n.bundle)
    case .titleAndTime:
      String(
        localized: "calendar.duplicates.titleTime.detail",
        defaultValue:
          "Combine events with the same title and exact times. Locations and other details may differ; choose a calendar in event details to see each copy.",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
  }
}

public struct CalendarEventCopyPicker: View {
  let copies: [CalendarTimelineEvent]
  @Binding var selectedID: String

  public init(copies: [CalendarTimelineEvent], selectedID: Binding<String>) {
    self.copies = copies
    self._selectedID = selectedID
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Label(CalendarDuplicateCopy.combined, systemImage: "square.on.square")
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(.secondary)
      Picker(selection: $selectedID) {
        ForEach(
          copies.sorted {
            ($0.origin?.calendarID ?? "", $0.id) < ($1.origin?.calendarID ?? "", $1.id)
          }
        ) { event in
          HStack {
            Circle().fill(LorvexDesign.Palette.eventTint(event.color)).frame(width: 8, height: 8)
              .accessibilityHidden(true)
            Text(userContent: event.originDisplayName)
          }
          .tag(event.id)
        }
      } label: {
        Text(CalendarDuplicateCopy.combined)
      }
      .labelsHidden()
      #if os(macOS) || os(iOS)
      .pickerStyle(.menu)
      #endif
      .accessibilityLabel(CalendarDuplicateCopy.combined)
      .accessibilityIdentifier("calendar.event.sourceCopy")
    }
  }
}

public enum CalendarDuplicateCopy {
  public static var combined: String {
    String(
      localized: "calendar.duplicates.combined", defaultValue: "Combined Event",
      table: "Localizable", bundle: CoreL10n.bundle)
  }
}

public struct CalendarCombinedEventMark: View {
  public init() {}
  public var body: some View {
    Image(systemName: "square.on.square")
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .accessibilityLabel(CalendarDuplicateCopy.combined)
  }
}

extension CalendarTimelineEvent {
  public var originDisplayName: String {
    guard let origin else { return source }
    return [origin.calendarTitle, origin.accountTitle].compactMap { $0 }
      .filter { !$0.isEmpty }.joined(separator: " · ")
  }
}
