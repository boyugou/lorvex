import LorvexCore
import SwiftUI

/// The Time Zone rows in Settings: the synced zone every device counts
/// Lorvex's days in, shown as its city and current offset in the user's
/// language ("Los Angeles · GMT-7", "洛杉矶 · GMT-7") on a row that pushes a
/// searchable list of zones. When this device
/// is in another zone, a second row offers to switch to it in one tap, which
/// is what a move or a long trip needs; a short trip can keep the home zone.
struct MobileSettingsTimeZoneRow: View {
  @Bindable var store: MobileStore
  @State private var isPickerPresented = false
  @State private var selection = LorvexTimeZoneSelection()

  var body: some View {
    // A navigation link, so the row carries the system chevron and lines up
    // with the Language and Clock pickers above it.
    NavigationLink {
      picker
    } label: {
      LabeledContent(Copy.title) {
        Text(LorvexTimeZoneChoice(identifier: store.logicalTimezoneName)?.summary
          ?? store.logicalTimezoneName)
      }
    }
    .disabled(selection.isSaving)
    .accessibilityIdentifier("mobileSettings.timeZone")
    #if DEBUG
      // Dev/QA only: `-lorvexOpenTimeZonePicker` pushes the list so the
      // simulator capture can show it.
      .navigationDestination(isPresented: $isPickerPresented) { picker }
      .onAppear {
        if CommandLine.arguments.contains("-lorvexOpenTimeZonePicker") { isPickerPresented = true }
      }
    #endif

    if let device = LorvexTimeZoneChoice(identifier: TimeZone.current.identifier),
      device.identifier != store.logicalTimezoneName
    {
      Button {
        Task { await choose(device.identifier) }
      } label: {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Text(Copy.useDevice(device.summary))
          if selection.pendingIdentifier == device.identifier {
            ProgressView().environment(\.isEnabled, true)
          }
        }
      }
      .disabled(selection.isSaving)
      .accessibilityIdentifier("mobileSettings.timeZone.useDevice")
    }
  }

  private var picker: some View {
    MobileTimeZonePicker(
      selected: store.logicalTimezoneName, pendingIdentifier: selection.pendingIdentifier,
      choose: choose)
  }

  @discardableResult
  private func choose(_ identifier: String) async -> Bool {
    await selection.select(identifier, current: store.logicalTimezoneName) {
      await store.setLogicalTimeZone($0)
    }
  }

  enum Copy {
    static var title: String {
      String(
        localized: "settings.time_zone", defaultValue: "Time Zone", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    static var caption: String {
      String(
        localized: "settings.time_zone.caption",
        defaultValue: "Lorvex counts days in this time zone on all your devices.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    static func useDevice(_ zone: String) -> String {
      String(
        localized: "settings.time_zone.use_device",
        defaultValue: "Use This Device’s Time Zone (\(zone))", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    static var search: String {
      String(
        localized: "settings.time_zone.search", defaultValue: "City or time zone",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

/// The time zone list behind the Time Zone row: every zone west to east, each
/// with its generic name under the city and its offset at the trailing edge,
/// searchable by city, region, or name. The chosen zone carries a checkmark
/// and is scrolled into view on open; choosing a zone saves it and goes back.
private struct MobileTimeZonePicker: View {
  let selected: String
  let pendingIdentifier: String?
  let choose: (String) async -> Bool

  @State private var query = ""
  @State private var choices: [LorvexTimeZoneChoice] = []
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let shown = choices.filter { $0.matches(query) }
    ScrollViewReader { proxy in
      List(shown) { choice in
        Button {
          Task {
            if await choose(choice.identifier) { dismiss() }
          }
        } label: {
          row(choice)
        }
        .foregroundStyle(.primary)
        .id(choice.identifier)
        .accessibilityAddTraits(choice.identifier == selected ? .isSelected : [])
      }
      .disabled(pendingIdentifier != nil)
      .overlay {
        if shown.isEmpty, !choices.isEmpty {
          MobileEmptyState.search(text: query)
        }
      }
      .onChange(of: choices.isEmpty) { _, _ in proxy.scrollTo(selected, anchor: .center) }
    }
    #if os(iOS)
      // Always shown: the list opens scrolled to the chosen zone, and a field in the
      // default hiding drawer would start out of sight above it.
      .searchable(
        text: $query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: MobileSettingsTimeZoneRow.Copy.search)
    #else
      .searchable(text: $query, prompt: MobileSettingsTimeZoneRow.Copy.search)
    #endif
    .navigationTitle(MobileSettingsTimeZoneRow.Copy.title)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task(id: selected) {
      let kept: Set<String> = [selected]
      let loaded = await Task.detached { LorvexTimeZoneChoice.all(keeping: kept) }.value
      guard !Task.isCancelled else { return }
      choices = loaded
    }
  }

  private func row(_ choice: LorvexTimeZoneChoice) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(choice.city)
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
      ZStack {
        Image(systemName: "checkmark")
          .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
          .foregroundStyle(LorvexDesign.Palette.accent)
          .opacity(choice.identifier == selected && choice.identifier != pendingIdentifier ? 1 : 0)
        if choice.identifier == pendingIdentifier { ProgressView().environment(\.isEnabled, true) }
      }
      .frame(width: 20)
    }
    .contentShape(Rectangle())
  }
}
