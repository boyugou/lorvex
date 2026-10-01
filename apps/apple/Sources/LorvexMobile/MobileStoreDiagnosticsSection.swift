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
    Section {
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
        // Rows, not user edits — one edit stages the entity write plus its
        // `ai_changelog` envelope. Named for what it counts so it is not read as
        // a change count; Cloud Sync shows the state this depth implies instead.
        LabeledContent(
          String(
            localized: "diagnostics.pending_rows", defaultValue: "Pending Sync Rows",
            table: "Localizable", bundle: MobileL10n.bundle),
          value: "\(store.syncPendingRowCount)")
        // Only meaningful while something is queued, and a constant zero next
        // to an empty queue is noise.
        if store.syncPendingRowCount > 0 {
          LabeledContent(
            String(
              localized: "diagnostics.retrying_rows", defaultValue: "Retrying Sync Rows",
              table: "Localizable", bundle: MobileL10n.bundle),
            value: "\(store.syncRetryingRowCount)")
        }
        if let lastError = store.syncStatus?.lastError {
          // The transport's own words for why a row did not upload, so it wraps
          // and stays selectable instead of being clipped to a `LabeledContent`
          // trailing value — a truncated CloudKit message diagnoses nothing.
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            Text(
              String(
                localized: "settings.sync.last_error", defaultValue: "Last Error",
                table: "Localizable", bundle: MobileL10n.bundle)
            )
            .font(LorvexDesign.Typography.secondaryText)
            Text(lastError)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(LorvexDesign.Palette.error)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("mobileDiagnostics.syncLastError")
        }
      } else {
        // Bounded empty state — a raw `ContentUnavailableView` in a `List`
        // `Section` inflates the row to a tall centered block (see
        // `MobileEmptyState`).
        MobileEmptyState(
          icon: "waveform.path.ecg",
          title: String(
            localized: "diagnostics.empty", defaultValue: "No Diagnostics", table: "Localizable",
            bundle: MobileL10n.bundle))
      }
    } header: {
      Text(
        String(
          localized: "diagnostics.section", defaultValue: "Diagnostics", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
  }

  /// Read-only feed of the most recent failures: MetricKit crash / hang / CPU /
  /// disk rows recorded by the system, and the app's own `error`-level rows
  /// (Cloud Sync cycles, failed user actions). Newest-first over the
  /// `error_logs` diagnostics ring.
  @ViewBuilder
  private var recentDiagnosticsSection: some View {
    let entries = store.recentDiagnosticLogs
    Section {
      if entries.isEmpty {
        Text(
          String(
            localized: "diagnostics.recent.empty",
            defaultValue: "No failures recorded. Crashes and errors appear here.",
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
            "Crashes and resource exceptions the system reports to Lorvex, plus errors Lorvex recorded itself, newest first. Tap a row to see its full detail.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
    .accessibilityIdentifier("mobileDiagnostics.recent")
  }
}
