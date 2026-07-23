import LorvexCore
import SwiftUI

struct MobileStoreDiagnosticsSection: View {
  @Bindable var store: MobileStore

  /// Cap on rows rendered from ``MobileStore/recentDiagnosticLogs``, keeping the
  /// Settings list from growing tall on a device with many logged diagnostics.
  private let recentDiagnosticsLimit = 12

  var body: some View {
    Group {
      summarySection
      recentDiagnosticsSection
    }
  }

  private var summarySection: some View {
    Section(
      String(
        localized: "diagnostics.section", defaultValue: "Diagnostics", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      if let diagnostics = store.runtimeDiagnostics {
        LabeledContent(
          String(
            localized: "diagnostics.setup", defaultValue: "Setup", table: "Localizable",
            bundle: MobileL10n.bundle),
          value: diagnostics.setup.setupCompleted
            ? String(
              localized: "diagnostics.setup.complete", defaultValue: "Complete",
              table: "Localizable", bundle: MobileL10n.bundle)
            : String(
              localized: "diagnostics.setup.needs_setup", defaultValue: "Needs setup",
              table: "Localizable", bundle: MobileL10n.bundle))
        LabeledContent(
          String(
            localized: "diagnostics.tasks", defaultValue: "Tasks", table: "Localizable",
            bundle: MobileL10n.bundle), value: "\(diagnostics.setup.taskCount)")
        LabeledContent(
          String(
            localized: "diagnostics.lists", defaultValue: "Lists", table: "Localizable",
            bundle: MobileL10n.bundle), value: "\(diagnostics.setup.listCount)")
        LabeledContent(
          String(
            localized: "diagnostics.sync", defaultValue: "Sync", table: "Localizable",
            bundle: MobileL10n.bundle), value: store.cloudSyncBackendLabel)
        LabeledContent(
          String(
            localized: "diagnostics.pending", defaultValue: "Pending", table: "Localizable",
            bundle: MobileL10n.bundle), value: "\(diagnostics.sync.pendingCount)")
        if let lastError = diagnostics.sync.lastError {
          LabeledContent(
            String(
              localized: "settings.sync.last_error", defaultValue: "Last Error",
              table: "Localizable", bundle: MobileL10n.bundle), value: lastError)
        }
        Text(diagnostics.guide.summary)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      } else {
        ContentUnavailableView(
          String(
            localized: "diagnostics.empty", defaultValue: "No Diagnostics", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "waveform.path.ecg")
      }
      Button {
        Task { await store.loadRuntimeDiagnostics() }
      } label: {
        Label(
          String(
            localized: "diagnostics.refresh", defaultValue: "Refresh Diagnostics",
            table: "Localizable", bundle: MobileL10n.bundle), systemImage: "arrow.clockwise")
      }
      .disabled(store.isLoadingRuntimeDiagnostics)
      .accessibilityIdentifier("mobileDiagnostics.refresh")
    }
  }

  /// Read-only feed of the most recent diagnostics, including MetricKit crash /
  /// hang / CPU / disk rows recorded by the system. Newest-first over the
  /// `error_logs` diagnostics ring.
  @ViewBuilder
  private var recentDiagnosticsSection: some View {
    let entries = store.recentDiagnosticLogs
    Section {
      if entries.isEmpty {
        Text(
          String(
            localized: "diagnostics.recent.empty",
            defaultValue: "No crashes or hangs recorded. System-captured diagnostics appear here.",
            table: "Localizable", bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("mobileDiagnostics.recent.empty")
      } else {
        ForEach(entries.prefix(recentDiagnosticsLimit)) { entry in
          MobileDiagnosticLogRow(entry: entry, now: store.now())
        }
      }
    } header: {
      Text(
        String(
          localized: "diagnostics.recent.section", defaultValue: "Recent Diagnostics",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(
        String(
          localized: "diagnostics.recent.footer",
          defaultValue:
            "Crashes, hangs, and resource exceptions the system reports to Lorvex, newest first.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
    .accessibilityIdentifier("mobileDiagnostics.recent")
  }
}
