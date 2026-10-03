import AppKit
import LorvexCore
import SwiftUI

// MARK: - Diagnostics tab: setup, Apple surfaces, activity, and about

extension SettingsView {
  @ViewBuilder
  var diagnosticsSection: some View {
    if store.runtimeDiagnostics?.sync.reseedRequired == true {
      reseedRequiredBanner
    }

    if let diagnostics = store.runtimeDiagnostics {
      Section(String(localized: "settings.diagnostics.overview_section", defaultValue: "Overview", table: "Localizable", bundle: LorvexL10n.bundle)) {
        SettingsDiagnosticsPanel(
          rows: setupDiagnosticRows(diagnostics),
          accessibilityIdentifier: "settings.diagnostics.setupPanel"
        )
      }

      Section(String(localized: "settings.diagnostics.apple_surfaces", defaultValue: "Apple Surfaces", table: "Localizable", bundle: LorvexL10n.bundle)) {
        SettingsDiagnosticsPanel(
          rows: appleSurfaceDiagnosticRows,
          accessibilityIdentifier: "settings.diagnostics.appleSurfacesPanel"
        )
      }
    } else {
      Section(String(localized: "settings.tab.diagnostics", defaultValue: "Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle)) {
        noDiagnosticsPlaceholder
      }
    }
  }

  /// Read-only warning shown when the core has recorded the `reseed_required`
  /// sync checkpoint (horizon GC dropped un-applied inbound data). It states that
  /// a full re-sync is needed; the core clears the marker on its own after a
  /// successful re-sync, so this surface never mutates it.
  private var reseedRequiredBanner: some View {
    Section {
      Label {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(String(
            localized: "settings.diagnostics.reseed_required.title",
            defaultValue: "Full re-sync needed",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
            .font(LorvexDesign.Typography.primaryEmphasis)
          Text(String(
            localized: "settings.diagnostics.reseed_required.message",
            defaultValue: "Some records could not be synced and may need a full re-sync.",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } icon: {
        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(LorvexDesign.Palette.warning)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("settings.diagnostics.reseedRequired")
    }
  }

  private func setupDiagnosticRows(_ diagnostics: RuntimeDiagnosticsSnapshot) -> [SettingsDiagnosticsRow] {
    var rows = [
      SettingsDiagnosticsRow(
        id: "setup",
        title: String(localized: "settings.diagnostics.setup", defaultValue: "Setup", table: "Localizable", bundle: LorvexL10n.bundle),
        value: diagnostics.setup.setupCompleted
          ? String(localized: "settings.diagnostics.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle)
          : String(localized: "settings.diagnostics.needs_setup", defaultValue: "Needs setup", table: "Localizable", bundle: LorvexL10n.bundle),
        detail: nil,
        systemImage: diagnostics.setup.setupCompleted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
        level: diagnostics.setup.setupCompleted ? .success : .warning
      ),
      SettingsDiagnosticsRow(
        id: "lists",
        title: String(localized: "settings.diagnostics.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle),
        value: diagnostics.setup.listCount.formatted(),
        detail: nil,
        systemImage: "folder",
        level: .neutral
      ),
      SettingsDiagnosticsRow(
        id: "tasks",
        title: String(localized: "settings.diagnostics.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
        value: diagnostics.setup.taskCount.formatted(),
        detail: nil,
        systemImage: "checklist",
        level: .neutral
      ),
    ]

    if let defaultListID = diagnostics.setup.defaultListID {
      rows.append(SettingsDiagnosticsRow(
        id: "default-list",
        title: String(localized: "settings.diagnostics.default_list", defaultValue: "Default List", table: "Localizable", bundle: LorvexL10n.bundle),
        value: store.lists?.lists.first { $0.id == defaultListID }?.displayName ?? defaultListID,
        detail: nil,
        systemImage: "tray.full",
        level: .neutral
      ))
    }

    return rows
  }

  private var appleSurfaceDiagnosticRows: [SettingsDiagnosticsRow] {
    let surfaces = store.appleSurfaceDiagnostics
    return [
      surfaceRow(
        id: "spotlight",
        title: String(localized: "settings.diagnostics.spotlight", defaultValue: "Spotlight", table: "Localizable", bundle: LorvexL10n.bundle),
        status: surfaces.spotlight,
        systemImage: "magnifyingglass"
      ),
      surfaceRow(
        id: "task-reminders",
        title: String(localized: "settings.diagnostics.task_reminders", defaultValue: "Task Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
        status: surfaces.taskReminders,
        systemImage: "bell"
      ),
      surfaceRow(
        id: "habit-reminders",
        title: String(localized: "settings.diagnostics.habit_reminders", defaultValue: "Habit Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
        status: surfaces.habitReminders,
        systemImage: "bell.badge"
      ),
      surfaceRow(
        id: "calendar-import",
        title: String(localized: "settings.diagnostics.calendar_import", defaultValue: "Calendar Import", table: "Localizable", bundle: LorvexL10n.bundle),
        status: surfaces.calendarImport,
        systemImage: "calendar.badge.clock"
      ),
      surfaceRow(
        id: "widget",
        title: String(localized: "settings.diagnostics.widget_snapshot", defaultValue: "Widget Snapshot", table: "Localizable", bundle: LorvexL10n.bundle),
        status: surfaces.widget,
        systemImage: "rectangle.inset.filled"
      ),
      SettingsDiagnosticsRow(
        id: "widget-today",
        title: String(localized: "settings.diagnostics.widget_today_tasks", defaultValue: "Widget Today Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
        value: surfaces.widgetTodayTaskCount.formatted(),
        detail: nil,
        systemImage: "sun.max",
        level: .neutral
      ),
    ]
  }

  /// A row for one Apple surface: its state, the line under it, and a warning
  /// color on the icon only when the state needs attention.
  private func surfaceRow(
    id: String, title: String, status: AppleSurfaceDiagnostics.Status, systemImage: String
  ) -> SettingsDiagnosticsRow {
    SettingsDiagnosticsRow(
      id: id,
      title: title,
      value: status.value,
      detail: status.detail,
      systemImage: systemImage,
      level: status.needsAttention ? .warning : .neutral
    )
  }

  private var noDiagnosticsPlaceholder: some View {
    LorvexEmptyStatePanel(
      title: String(localized: "settings.diagnostics.no_diagnostics", defaultValue: "No Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "settings.diagnostics.no_diagnostics_description",
        defaultValue: "Lorvex hasn’t read its diagnostics yet.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "waveform.path.ecg",
      tint: .accentColor,
      chips: [
        LorvexEmptyStateChip(
          title: String(localized: "settings.tab.diagnostics", defaultValue: "Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "waveform.path.ecg",
          tint: .accentColor
        )
      ]
    ) {
      Button {
        Task { await store.loadRuntimeDiagnostics() }
      } label: {
        Label(
          String(localized: "settings.runtime.refresh_diagnostics", defaultValue: "Refresh Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.triangle.2.circlepath"
        )
      }
    }
  }

  /// App version, a plaintext diagnostics summary to copy into a bug report,
  /// and the acknowledgments and privacy policy. Each row names its content
  /// on the leading side with the action or a chevron at the trailing edge.
  /// There is no refresh action: the diagnostics reload whenever this tab
  /// opens and on every app refresh.
  var aboutSection: some View {
    Section(String(localized: "settings.section.about", defaultValue: "About", table: "Localizable", bundle: LorvexL10n.bundle)) {
      LabeledContent(
        String(localized: "settings.runtime.version", defaultValue: "Version", table: "Localizable", bundle: LorvexL10n.bundle),
        value: AppMetadata.displayVersion
      )
      .textSelection(.enabled)
      .accessibilityIdentifier("settings.runtime.overview.version")

      LabeledContent {
        Button {
          let text = diagnosticsClipboardText()
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
          diagnosticsCopied = true
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            diagnosticsCopied = false
          }
        } label: {
          SettingsCopyButtonTitle(copied: diagnosticsCopied)
        }
        .accessibilityLabel(String(localized: "settings.diagnostics.copy", defaultValue: "Copy Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("settings.diagnostics.copy")
      } label: {
        Label(
          String(localized: "settings.diagnostics.summary", defaultValue: "Diagnostics Summary", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "doc.on.doc")
      }

      SettingsSheetLinkRow(
        title: String(localized: "settings.acknowledgments.open", defaultValue: "Acknowledgments", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "doc.text"
      ) {
        showingAcknowledgments = true
      }
      .accessibilityIdentifier("settings.acknowledgments.open")

      SettingsSheetLinkRow(
        title: String(localized: "settings.privacy.open", defaultValue: "Privacy Policy", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "hand.raised"
      ) {
        showingPrivacyPolicy = true
      }
      .accessibilityIdentifier("settings.privacy.open")
    }
  }

  /// Cloud Sync backend derived from the effective ``AppStore/cloudSyncMode``:
  /// `.off` reads "disabled" and `.live` reads "cloudkit". The core's
  /// `SyncStatusSnapshot.backend` is a static placeholder that cannot see the
  /// mode, so the bug-report text sources the label from the store instead.
  private var syncBackendLabel: String {
    switch store.cloudSyncMode {
    case .off: return "disabled"
    case .live: return "cloudkit"
    }
  }

  /// Plaintext snapshot of the current runtime diagnostics (version, setup
  /// counts, sync backend/pending/failed, and Apple-surface statuses) for
  /// pasting into a bug report. Returns a version-only line when no diagnostics
  /// have been loaded yet.
  func diagnosticsClipboardText() -> String {
    var lines = ["Lorvex \(AppMetadata.displayVersion)"]

    if let diagnostics = store.runtimeDiagnostics {
      let setup = diagnostics.setup
      lines.append(
        "Setup: \(setup.setupCompleted ? "complete" : "needs setup")"
          + " (lists \(setup.listCount), tasks \(setup.taskCount))"
      )

      let sync = diagnostics.sync
      lines.append(
        "Sync: \(syncBackendLabel)"
          + " (pending \(sync.pendingCount), failed \(sync.failedCount))"
      )
      if let lastError = sync.lastError, !lastError.isEmpty {
        lines.append("Sync error: \(lastError)")
      }
    } else {
      lines.append("Diagnostics: not loaded")
    }

    let surfaces = store.appleSurfaceDiagnostics
    func line(_ label: String, _ status: AppleSurfaceDiagnostics.Status) -> String {
      guard let detail = status.detail, !detail.isEmpty else { return "\(label): \(status.value)" }
      return "\(label): \(status.value) (\(detail))"
    }
    lines.append(line("Spotlight", surfaces.spotlight))
    lines.append(line("Task Reminders", surfaces.taskReminders))
    lines.append(line("Habit Reminders", surfaces.habitReminders))
    lines.append(line("Calendar Import", surfaces.calendarImport))
    lines.append(line("Widget Snapshot", surfaces.widget))
    lines.append("Widget Today Tasks: \(surfaces.widgetTodayTaskCount)")

    return lines.joined(separator: "\n")
  }
}
