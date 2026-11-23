import SwiftUI

#if os(macOS)
  import AppKit
#endif

/// The daily backups section of Settings › Data on the Mac and iPhone: a switch
/// for keeping backups on this device (``LorvexDailyBackupServicing``), the
/// date of the latest backup, and a way to reach the files. On iPhone and iPad
/// the latest backup row opens the list of backups, each with a share button;
/// on the Mac it reveals the newest backup in Finder. Turning backups off while
/// some are kept asks first, because it deletes them. The latest backup row
/// shows while backups are on or any are still kept.
///
/// The section reloads when it appears and whenever `isDisabled` changes, so
/// an erase or import that finishes while it is on screen is reflected.
/// Renders nothing for a core that keeps no backups. The identifiers are
/// `\(idPrefix).toggle`, `\(idPrefix).latest`, `\(idPrefix).error`, and, on the
/// Mac, `\(idPrefix).showInFinder`.
public struct LorvexDailyBackupsSection: View {
  private let service: (any LorvexDailyBackupServicing)?
  private let isDisabled: Bool
  private let idPrefix: String
  private let backUpNow: @MainActor () async -> Void
  private let describeError: @MainActor (Error) async -> String

  @State private var isEnabled = true
  @State private var backups: [LorvexDailyBackup] = []
  @State private var isLoaded = false
  @State private var isApplying = false
  @State private var isConfirmingTurnOff = false
  @State private var errorMessage: String?
  @Environment(\.locale) private var locale

  /// - Parameters:
  ///   - isDisabled: true while the host is erasing or importing this
  ///     device's data.
  ///   - backUpNow: runs one backup pass for the host's logical day; called
  ///     after backups are turned on, before the section reloads.
  ///   - describeError: the sentence shown when turning backups on or off
  ///     fails; the host's user-facing error text, which also logs the error.
  public init(
    core: any LorvexCoreServicing,
    isDisabled: Bool,
    idPrefix: String,
    backUpNow: @escaping @MainActor () async -> Void,
    describeError: @escaping @MainActor (Error) async -> String
  ) {
    self.service = core as? any LorvexDailyBackupServicing
    self.isDisabled = isDisabled
    self.idPrefix = idPrefix
    self.backUpNow = backUpNow
    self.describeError = describeError
  }

  public var body: some View {
    if service != nil {
      Section {
        Toggle(isOn: Binding(get: { isEnabled }, set: { request($0) })) {
          Text(Strings.toggle)
        }
        .disabled(isDisabled || isApplying || !isLoaded)
        .accessibilityIdentifier("\(idPrefix).toggle")
        .task(id: isDisabled) { await reload() }
        .confirmationDialog(
          Strings.turnOffTitle, isPresented: $isConfirmingTurnOff, titleVisibility: .visible
        ) {
          Button(Strings.turnOffConfirm, role: .destructive) { apply(false) }
          Button(Strings.cancel, role: .cancel) { isEnabled = true }
        } message: {
          Text(Strings.turnOffMessage)
        }
        .onChange(of: isConfirmingTurnOff) { _, isPresented in
          // A dialog dismissed without either button (a tap outside it on
          // iPad) leaves the switch showing off; read the stored value back.
          // The task runs after the button's own action, so Turn Off has
          // already started applying by then.
          guard !isPresented else { return }
          Task { @MainActor in if !isApplying { await reload() } }
        }

        if isLoaded, isEnabled || !backups.isEmpty { latestRow }

        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(LorvexDesign.Palette.warning)
            .accessibilityIdentifier("\(idPrefix).error")
        }
      } header: {
        Text(Strings.title)
      } footer: {
        Text(Strings.footer)
      }
    }
  }

  @ViewBuilder private var latestRow: some View {
    #if os(macOS)
      LabeledContent {
        HStack(spacing: LorvexDesign.Spacing.s) {
          latestValue
          if let newest = backups.first {
            Button(Strings.showInFinder) {
              NSWorkspace.shared.activateFileViewerSelecting([newest.url])
            }
            .accessibilityIdentifier("\(idPrefix).showInFinder")
          }
        }
      } label: {
        Text(Strings.latest)
      }
      .accessibilityIdentifier("\(idPrefix).latest")
    #else
      if backups.isEmpty {
        LabeledContent { latestValue } label: { Text(Strings.latest) }
          .accessibilityIdentifier("\(idPrefix).latest")
      } else {
        NavigationLink {
          LorvexDailyBackupsList(backups: backups)
        } label: {
          LabeledContent { latestValue } label: { Text(Strings.latest) }
        }
        .accessibilityIdentifier("\(idPrefix).latest")
      }
    #endif
  }

  @ViewBuilder private var latestValue: some View {
    if let newest = backups.first {
      Text(verbatim: LorvexDailyBackupDay.label(newest.day, .abbreviated, locale))
    } else {
      Text(Strings.noneYet)
    }
  }

  /// Turning backups off while some are kept shows the switch off and asks
  /// first; Cancel puts it back. Every other change applies at once.
  private func request(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    if !enabled, !backups.isEmpty {
      isEnabled = false
      isConfirmingTurnOff = true
    } else {
      apply(enabled)
    }
  }

  /// Saves the switch, then reloads what is on disk. The switch shows the new
  /// position at once; a failure puts it back and says why.
  private func apply(_ enabled: Bool) {
    guard let service else { return }
    isEnabled = enabled
    isApplying = true
    errorMessage = nil
    Task { @MainActor in
      defer { isApplying = false }
      do {
        try await service.setDailyBackupsEnabled(enabled)
        if enabled { await backUpNow() }
      } catch {
        errorMessage = await describeError(error)
      }
      await reload()
    }
  }

  /// Reads the switch and the backups. A failed read of the switch keeps the
  /// position the section already shows.
  private func reload() async {
    guard let service else { return }
    if let enabled = try? await service.dailyBackupsEnabled() { isEnabled = enabled }
    backups = (try? service.dailyBackups()) ?? []
    isLoaded = true
  }
}

#if !os(macOS)
  /// Every daily backup on this device, newest first, each with its size and a
  /// share button. Each share button's identifier is
  /// `dailyBackups.share.<day>`.
  public struct LorvexDailyBackupsList: View {
    let backups: [LorvexDailyBackup]
    @Environment(\.locale) private var locale

    public init(backups: [LorvexDailyBackup]) { self.backups = backups }

    public var body: some View {
      List {
        Section {
          ForEach(backups) { backup in
            row(backup)
          }
        } footer: {
          Text(Strings.listFooter)
        }
      }
      .navigationTitle(Strings.title)
    }

    private func row(_ backup: LorvexDailyBackup) -> some View {
      let label = LorvexDailyBackupDay.label(backup.day, .complete, locale)
      return HStack(spacing: LorvexDesign.Spacing.m) {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(verbatim: label)
          Text(Int64(backup.byteCount).formatted(.byteCount(style: .file).locale(locale)))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        Spacer(minLength: LorvexDesign.Spacing.s)
        ShareLink(item: backup.url) {
          Image(systemName: "square.and.arrow.up")
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(String(format: Strings.share, label))
        .accessibilityIdentifier("dailyBackups.share.\(backup.day)")
      }
    }
  }
#endif

/// A backup's logical day written out in `locale`'s own calendar. The day is
/// midnight UTC of `yyyy-MM-dd` and is formatted in UTC, so the day shown is
/// the day named in any time zone. The label is formatted here rather than by
/// `Text(_:format:)`, which formats in the environment's time zone and would
/// show the day before west of UTC.
private enum LorvexDailyBackupDay {
  static func label(_ day: String, _ dateStyle: Date.FormatStyle.DateStyle, _ locale: Locale)
    -> String
  {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: day) else { return day }
    let utc = TimeZone(identifier: "UTC") ?? .gmt
    let style = Date.FormatStyle(
      date: dateStyle, time: .omitted, locale: locale,
      calendar: LorvexDateFormatters.displayCalendar(timeZone: utc, locale: locale),
      timeZone: utc)
    return date.formatted(style)
  }
}

private enum Strings {
  static var title: String {
    String(
      localized: "settings.daily_backups.title", defaultValue: "Daily Backups",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Settings › Data: title of the section about the automatic daily backups.")
  }

  static var toggle: String {
    String(
      localized: "settings.daily_backups.toggle", defaultValue: "Keep Daily Backups",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Switch that turns the automatic daily backups on this device on or off.")
  }

  static var latest: String {
    String(
      localized: "settings.daily_backups.latest", defaultValue: "Latest Backup",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Row label; its value is the date of the newest daily backup.")
  }

  static var noneYet: String {
    String(
      localized: "settings.daily_backups.none_yet", defaultValue: "None yet",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Value of the Latest Backup row before the first daily backup is saved.")
  }

  static var showInFinder: String {
    String(
      localized: "settings.daily_backups.show_in_finder", defaultValue: "Show in Finder",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Mac button that opens Finder at the newest daily backup file.")
  }

  /// On the Mac the footer ends by pointing at the assistant, which reads the
  /// Mac's backups through the MCP server; iPhone and iPad have no such server.
  static var footer: String {
    #if os(macOS)
      String(
        localized: "settings.daily_backups.footer",
        defaultValue:
          "Once a day, Lorvex saves a copy of your data on this device. It keeps the last 7 days and one copy from each of the 4 weeks before. The copies stay on this device and are not synced. Items you delete stay in them until they age out. To bring something back, ask your assistant to compare your data with a backup.",
        table: "Localizable", bundle: CoreL10n.bundle,
        comment: "Footer under the daily backups switch.")
    #else
      String(
        localized: "settings.daily_backups.footer_mobile",
        defaultValue:
          "Once a day, Lorvex saves a copy of your data on this device. It keeps the last 7 days and one copy from each of the 4 weeks before. The copies stay on this device and are not synced. Items you delete stay in them until they age out.",
        table: "Localizable", bundle: CoreL10n.bundle,
        comment:
          "Footer under the daily backups switch on iPhone and iPad, where no assistant can read the backups."
      )
    #endif
  }

  static var listFooter: String {
    String(
      localized: "settings.daily_backups.list_footer",
      defaultValue:
        "Share a backup to keep a copy somewhere else. Lorvex can import it like any export.",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Footer under the list of daily backups on iPhone and iPad.")
  }

  static var turnOffTitle: String {
    String(
      localized: "settings.daily_backups.turn_off.title",
      defaultValue: "Turn off daily backups?",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Title of the confirmation shown before daily backups are turned off.")
  }

  static var turnOffMessage: String {
    String(
      localized: "settings.daily_backups.turn_off.message",
      defaultValue: "Lorvex deletes the backups it has kept on this device.",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Message of the confirmation shown before daily backups are turned off.")
  }

  static var turnOffConfirm: String {
    String(
      localized: "settings.daily_backups.turn_off.confirm", defaultValue: "Turn Off",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "Destructive button that turns daily backups off and deletes them.")
  }

  static var cancel: String {
    String(localized: "common.cancel", defaultValue: "Cancel", bundle: CoreL10n.bundle)
  }

  /// `%@` is the backup's date, written out.
  static var share: String {
    String(
      localized: "settings.daily_backups.share", defaultValue: "Share the backup from %@",
      table: "Localizable", bundle: CoreL10n.bundle,
      comment: "VoiceOver label of a backup's share button. %@ is the backup's date.")
  }
}
