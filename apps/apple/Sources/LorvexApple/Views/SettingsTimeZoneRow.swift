import LorvexCore
import SwiftUI

/// The Time Zone rows in Settings › General: the synced zone every device
/// counts Lorvex's days in, shown as its city and current offset in the
/// user's language ("Los Angeles · GMT-7", "洛杉矶 · GMT-7") on a button that
/// opens a searchable list of zones. When this Mac is in another zone, a
/// second row offers to switch to it in one click, which is what a move or a
/// long trip needs; a short trip can keep the home zone. The enclosing group's
/// footer carries ``caption``, which says the zone applies on every device.
struct SettingsTimeZoneRow: View {
  @Bindable var store: AppStore

  @State private var isPickerPresented = false

  var body: some View {
    LabeledContent(Copy.title) {
      Button {
        isPickerPresented = true
      } label: {
        // Drawn like the pop-up buttons of the Language and Clock rows above
        // it: the value in the primary style, then the up-down chevron in a
        // filled circle, inset from the trailing edge as the pop-up bezel
        // insets its own so the three chevrons line up.
        HStack(spacing: LorvexDesign.Spacing.s) {
          Text(current?.summary ?? store.logicalTimezoneName)
            .foregroundStyle(.primary)
          Image(systemName: "chevron.up.chevron.down")
            .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background(.quaternary, in: Circle())
        }
        .padding(.trailing, LorvexDesign.Spacing.xs)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("settings.timeZone")
      .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
        SettingsTimeZonePicker(selected: store.logicalTimezoneName) { identifier in
          isPickerPresented = false
          Task { await store.setLogicalTimeZone(identifier) }
        }
      }
    }

    if let device, device.identifier != store.logicalTimezoneName {
      Button(Copy.useDevice(device.summary)) {
        Task { await store.setLogicalTimeZone(device.identifier) }
      }
      .buttonStyle(.plain)
      .foregroundStyle(LorvexDesign.Palette.accent)
      .accessibilityIdentifier("settings.timeZone.useDevice")
    }

  }

  /// The footnote for the group holding these rows.
  static var caption: String {
    String(localized: "settings.time_zone.caption", defaultValue: "Lorvex counts days in this time zone on all your devices.", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var current: LorvexTimeZoneChoice? {
    LorvexTimeZoneChoice(identifier: store.logicalTimezoneName)
  }

  private var device: LorvexTimeZoneChoice? {
    LorvexTimeZoneChoice(identifier: TimeZone.current.identifier)
  }

  fileprivate enum Copy {
    static var title: String {
      String(localized: "settings.time_zone", defaultValue: "Time Zone", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    static func useDevice(_ zone: String) -> String {
      String(localized: "settings.time_zone.use_device", defaultValue: "Use This Device’s Time Zone (\(zone))", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    static var search: String {
      String(localized: "settings.time_zone.search", defaultValue: "City or time zone", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    static var noMatch: String {
      String(localized: "settings.time_zone.no_match", defaultValue: "No matching time zones", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

/// The time zone list behind the Time Zone row: a search field over the
/// zones' cities, regions, and names, then every zone west to east, each with
/// its generic name under the city and its offset at the trailing edge. The
/// chosen zone carries a checkmark and is scrolled into view on open.
struct SettingsTimeZonePicker: View {
  let selected: String
  let choose: (String) -> Void

  @State private var query = ""
  @State private var choices: [LorvexTimeZoneChoice] = []
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField(SettingsTimeZoneRow.Copy.search, text: $query)
        .textFieldStyle(.roundedBorder)
        .focused($isSearchFocused)
        .padding(LorvexDesign.Spacing.m)
        .accessibilityIdentifier("settings.timeZone.search")
      Divider()
      let shown = choices.filter { $0.matches(query) }
      if shown.isEmpty, !choices.isEmpty {
        Text(SettingsTimeZoneRow.Copy.noMatch)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          List(shown) { choice in
            row(choice)
              .id(choice.identifier)
          }
          .listStyle(.plain)
          // The zones load after the list first appears; scroll once they do.
          .onChange(of: choices.isEmpty) { _, _ in proxy.scrollTo(selected, anchor: .center) }
        }
      }
    }
    .frame(width: 340, height: 400)
    .task {
      choices = LorvexTimeZoneChoice.all()
      isSearchFocused = true
    }
    .accessibilityIdentifier("settings.timeZone.picker")
  }

  private func row(_ choice: LorvexTimeZoneChoice) -> some View {
    Button {
      choose(choice.identifier)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        Image(systemName: "checkmark")
          .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
          .foregroundStyle(LorvexDesign.Palette.accent)
          .opacity(choice.identifier == selected ? 1 : 0)
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(choice.city)
            .font(LorvexDesign.Typography.primaryText)
          if !choice.genericName.isEmpty {
            Text(choice.genericName)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: LorvexDesign.Spacing.s)
        Text(choice.offsetLabel)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(choice.identifier == selected ? .isSelected : [])
    .accessibilityIdentifier("settings.timeZone.\(choice.identifier)")
  }
}
