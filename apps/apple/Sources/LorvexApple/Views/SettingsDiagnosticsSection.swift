import AppKit
import LorvexCore
import SwiftUI

// MARK: - Diagnostics tab: setup, Apple surfaces, guide, activity, and about

extension SettingsView {
  @ViewBuilder
  var diagnosticsSection: some View {
    if store.runtimeDiagnostics?.sync.reseedRequired == true {
      reseedRequiredBanner
    }

    if let diagnostics = store.runtimeDiagnostics {
      Section(String(localized: "settings.diagnostics.setup_section", defaultValue: "Setup", table: "Localizable", bundle: LorvexL10n.bundle)) {
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

      Section(String(localized: "settings.diagnostics.guide", defaultValue: "Guide", table: "Localizable", bundle: LorvexL10n.bundle)) {
        SettingsDiagnosticsGuidePanel(guide: diagnostics.guide)
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
        VStack(alignment: .leading, spacing: 3) {
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
          .foregroundStyle(.orange)
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
        value: "\(diagnostics.setup.listCount)",
        detail: nil,
        systemImage: "folder",
        level: .neutral
      ),
      SettingsDiagnosticsRow(
        id: "tasks",
        title: String(localized: "settings.diagnostics.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(diagnostics.setup.taskCount)",
        detail: nil,
        systemImage: "checklist",
        level: .neutral
      ),
    ]

    if let defaultListID = diagnostics.setup.defaultListID {
      rows.append(SettingsDiagnosticsRow(
        id: "default-list",
        title: String(localized: "settings.diagnostics.default_list", defaultValue: "Default List", table: "Localizable", bundle: LorvexL10n.bundle),
        value: store.lists?.lists.first { $0.id == defaultListID }?.name ?? defaultListID,
        detail: nil,
        systemImage: "tray.full",
        level: .neutral
      ))
    }

    return rows
  }

  private var appleSurfaceDiagnosticRows: [SettingsDiagnosticsRow] {
    let surfaces = store.appleSurfaceDiagnostics
    var rows = [
      SettingsDiagnosticsRow(
        id: "spotlight",
        title: String(localized: "settings.diagnostics.spotlight", defaultValue: "Spotlight", table: "Localizable", bundle: LorvexL10n.bundle),
        value: surfaces.spotlightStatus,
        detail: nil,
        systemImage: "magnifyingglass",
        level: .neutral
      ),
      SettingsDiagnosticsRow(
        id: "task-reminders",
        title: String(localized: "settings.diagnostics.task_reminders", defaultValue: "Task Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
        value: surfaces.reminderStatus,
        detail: store.lastTaskReminderScheduleReport.requestedCount > 0
          ? String(
            format: String(
              localized: "settings.diagnostics.reminder_requests.detail",
              defaultValue: "%lld requested",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
            store.lastTaskReminderScheduleReport.requestedCount
          )
          : nil,
        systemImage: "bell",
        level: .warning
      ),
      SettingsDiagnosticsRow(
        id: "habit-reminders",
        title: String(localized: "settings.diagnostics.habit_reminders", defaultValue: "Habit Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
        value: surfaces.habitReminderStatus,
        detail: store.lastHabitReminderScheduleReport.requestedCount > 0
          ? String(
            format: String(
              localized: "settings.diagnostics.reminder_requests.detail",
              defaultValue: "%lld requested",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
            store.lastHabitReminderScheduleReport.requestedCount
          )
          : nil,
        systemImage: "bell.badge",
        level: .warning
      ),
      SettingsDiagnosticsRow(
        id: "calendar-import",
        title: String(localized: "settings.diagnostics.calendar_import", defaultValue: "Calendar Import", table: "Localizable", bundle: LorvexL10n.bundle),
        value: surfaces.calendarImportStatus,
        detail: nil,
        systemImage: "calendar.badge.clock",
        level: .neutral
      ),
      SettingsDiagnosticsRow(
        id: "widget",
        title: String(localized: "settings.diagnostics.widget_snapshot", defaultValue: "Widget Snapshot", table: "Localizable", bundle: LorvexL10n.bundle),
        value: surfaces.widgetStatus,
        detail: surfaces.widgetGeneratedAt,
        systemImage: "rectangle.inset.filled",
        level: .neutral
      ),
      SettingsDiagnosticsRow(
        id: "widget-focus",
        title: String(localized: "settings.diagnostics.widget_focus_tasks", defaultValue: "Widget Focus Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(surfaces.widgetFocusTaskCount)",
        detail: nil,
        systemImage: "scope",
        level: .neutral
      ),
    ]

    if store.lastTaskReminderScheduleReport.requestedCount == 0 {
      rows[1].level = .neutral
    }
    if store.lastHabitReminderScheduleReport.requestedCount == 0 {
      rows[2].level = .neutral
    }

    return rows
  }

  private var noDiagnosticsPlaceholder: some View {
    LorvexEmptyStatePanel(
      title: String(localized: "settings.diagnostics.no_diagnostics", defaultValue: "No Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "settings.diagnostics.no_diagnostics_description",
        defaultValue: "Apply a runtime or refresh diagnostics.",
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

  /// App version plus the diagnostics maintenance actions: refresh the snapshot
  /// and copy a plaintext summary for bug reports.
  var aboutSection: some View {
    Section(String(localized: "settings.section.about", defaultValue: "About", table: "Localizable", bundle: LorvexL10n.bundle)) {
      LabeledContent(
        String(localized: "settings.runtime.version", defaultValue: "Version", table: "Localizable", bundle: LorvexL10n.bundle),
        value: AppMetadata.displayVersion
      )
      .textSelection(.enabled)
      .accessibilityIdentifier("settings.runtime.overview.version")

      Button {
        Task { await store.loadRuntimeDiagnostics() }
      } label: {
        Label(
          String(localized: "settings.runtime.refresh_diagnostics", defaultValue: "Refresh Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "waveform.path.ecg"
        )
      }
      .accessibilityIdentifier("settings.diagnostics.refresh")

      Button {
        let text = diagnosticsClipboardText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      } label: {
        Label(
          String(localized: "settings.diagnostics.copy", defaultValue: "Copy Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "doc.on.doc"
        )
      }
      .accessibilityIdentifier("settings.diagnostics.copy")

      Button {
        showingAcknowledgments = true
      } label: {
        Label(
          String(localized: "settings.acknowledgments.open", defaultValue: "Acknowledgments", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "doc.text"
        )
      }
      .accessibilityIdentifier("settings.acknowledgments.open")

      Button {
        showingPrivacyPolicy = true
      } label: {
        Label(
          String(localized: "settings.privacy.open", defaultValue: "Privacy Policy", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "hand.raised"
        )
      }
      .accessibilityIdentifier("settings.privacy.open")
    }
  }

  /// Cloud Sync backend derived from the effective ``AppStore/cloudSyncMode``:
  /// `.off` reads "disabled"; `.recordPlan` and `.live` read "cloudkit"
  /// (CloudKit is the transport whenever sync is engaged). The core's
  /// `SyncStatusSnapshot.backend` is a static placeholder that cannot see the
  /// mode, so the bug-report text sources the label from the store instead.
  private var syncBackendLabel: String {
    switch store.cloudSyncMode {
    case .off: return "disabled"
    case .recordPlan, .live: return "cloudkit"
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
    lines.append("Spotlight: \(surfaces.spotlightStatus)")
    lines.append("Task Reminders: \(surfaces.reminderStatus)")
    lines.append("Habit Reminders: \(surfaces.habitReminderStatus)")
    lines.append("Calendar Import: \(surfaces.calendarImportStatus)")
    lines.append("Widget Snapshot: \(surfaces.widgetStatus)")
    lines.append("Widget Focus Tasks: \(surfaces.widgetFocusTaskCount)")

    return lines.joined(separator: "\n")
  }
}
